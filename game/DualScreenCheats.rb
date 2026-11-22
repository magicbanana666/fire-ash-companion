#===============================================================================
# Dual Screen Cheats / PokeEditor backend (Fire Ash Companion)
# The companion app writes DualScreen/cmd.json; this plugin picks it up while
# you are on the overworld, applies it and writes DualScreen/cmd_result.json.
# Also exports DualScreen/editor.json (species/moves/items/natures lists) and
# DualScreen/perf.json (measured FPS).
#===============================================================================
module DualScreenCheats
  CMD_FILE    = "DualScreen/cmd.json"
  RESULT_FILE = "DualScreen/cmd_result.json"
  EDITOR_FILE = "DualScreen/editor.json"
  PERF_FILE   = "DualScreen/perf.json"
  STATS = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

  @frame = 0
  @force_species = nil   # "next wild Pokémon" cheat (session only, not saved)
  @force_shiny = false
  @editor_done = false

  def self.force_species; @force_species; end
  def self.force_shiny; @force_shiny; end
  @fps_frames = 0
  @fps_t = nil

  module_function

  #-----------------------------------------------------------------------------
  # Tiny JSON parser (objects, arrays, strings, numbers, true/false/null)
  #-----------------------------------------------------------------------------
  def parse_json(str)
    @s = str; @i = 0
    v = j_value
    v
  end

  def j_ws; @i += 1 while @i < @s.length && " \t\r\n".include?(@s[@i]); end

  def j_value
    j_ws
    c = @s[@i]
    case c
    when "{"
      @i += 1; h = {}; j_ws
      if @s[@i] == "}" then @i += 1; return h; end
      loop do
        j_ws; k = j_string; j_ws; @i += 1   # :
        h[k] = j_value; j_ws
        if @s[@i] == "," then @i += 1 else @i += 1; break end
      end
      h
    when "["
      @i += 1; a = []; j_ws
      if @s[@i] == "]" then @i += 1; return a; end
      loop do
        a.push(j_value); j_ws
        if @s[@i] == "," then @i += 1 else @i += 1; break end
      end
      a
    when "\"" then j_string
    when "t" then @i += 4; true
    when "f" then @i += 5; false
    when "n" then @i += 4; nil
    else
      st = @i
      @i += 1 while @i < @s.length && "+-0123456789.eE".include?(@s[@i])
      num = @s[st...@i]
      num.include?(".") || num.include?("e") ? num.to_f : num.to_i
    end
  end

  def j_string
    @i += 1   # opening quote
    out = +""
    while @i < @s.length
      c = @s[@i]
      if c == "\""
        @i += 1; break
      elsif c == "\\"
        n = @s[@i + 1]
        case n
        when "n" then out << "\n"
        when "t" then out << "\t"
        when "r" then out << "\r"
        when "u" then out << [@s[@i + 2, 4].to_i(16)].pack("U"); @i += 4
        else out << n
        end
        @i += 2
      else
        out << c; @i += 1
      end
    end
    out
  end

  #-----------------------------------------------------------------------------
  # Editor data (once per session)
  #-----------------------------------------------------------------------------
  def export_editor
    species = []
    GameData::Species.each do |sp|
      species.push({
        "id" => sp.id.to_s, "base" => sp.species.to_s, "form" => sp.form, "name" => sp.name,
        "fname" => (sp.form_name rescue nil), "num" => (sp.id_number rescue 0),
        "types" => [sp.type1, sp.type2].compact.uniq.map(&:to_s),
        "icon" => (GameData::Species.icon_filename(sp.species, sp.form) rescue nil)
      })
    end
    moves = []
    GameData::Move.each do |m|
      moves.push({ "id" => m.id.to_s, "name" => m.name, "type" => m.type.to_s,
                   "cat" => DualScreenExport::CATEGORIES[m.category] || "", "power" => m.base_damage,
                   "acc" => m.accuracy, "pp" => m.total_pp })
    end
    items = []
    GameData::Item.each do |it|
      items.push({ "id" => it.id.to_s, "name" => it.name, "pocket" => it.pocket,
                   "icon" => (GameData::Item.icon_filename(it.id) rescue nil) })
    end
    natures = []
    GameData::Nature.each do |n|
      ch = (n.stat_changes rescue []) || []
      up = ch.find { |c| c[1] > 0 }; dn = ch.find { |c| c[1] < 0 }
      natures.push({ "id" => n.id.to_s, "name" => n.name, "up" => (up ? up[0].to_s : nil), "down" => (dn ? dn[0].to_s : nil) })
    end
    DualScreenExport.write_file(EDITOR_FILE, DualScreenExport.json({
      "species" => species, "moves" => moves, "items" => items, "natures" => natures,
      "pockets" => (PokemonBag.pocketNames rescue []), "generated" => Time.now.to_i
    }))
    @editor_done = true
  end

  # Extra per-Pokémon fields for the editor (merged into party_info)
  def editor_fields(pkmn)
    abil = (pkmn.getAbilityList rescue []).map do |a|
      { "id" => a[0].to_s, "name" => (GameData::Ability.get(a[0]).name rescue a[0].to_s), "index" => a[1] }
    end
    learn = []
    begin
      sp = pkmn.species_data
      (sp.moves || []).each { |m| learn.push(m[1].to_s) }
      (sp.tutor_moves || []).each { |m| learn.push(m.to_s) }
      (sp.egg_moves || []).each { |m| learn.push(m.to_s) }
    rescue
    end
    {
      "sid"       => pkmn.species.to_s,
      "form"      => pkmn.form,
      "nature_id" => (pkmn.nature_id.to_s rescue nil),
      "ability_index" => (pkmn.ability_index rescue 0),
      "abilities" => abil,
      "item_id"   => (pkmn.item_id ? pkmn.item_id.to_s : nil rescue nil),
      "move_ids"  => (pkmn.moves || []).map { |m| m.id.to_s },
      "iv"        => STATS.map { |s| (pkmn.iv[s] rescue 0) },
      "ev"        => STATS.map { |s| (pkmn.ev[s] rescue 0) },
      "gender"    => (pkmn.gender rescue 2),
      "happiness" => (pkmn.happiness rescue 0),
      "learnset"  => learn.uniq
    }
  end

  #-----------------------------------------------------------------------------
  # Commands
  #-----------------------------------------------------------------------------
  def sym(v)
    return nil if v.nil? || v.to_s.empty?
    v.to_s.to_sym
  end

  def run(cmd)
    op = cmd["op"]
    case op
    when "money"
      $Trainer.money = cmd["value"].to_i
      "Money set to #{$Trainer.money}"
    when "item"
      id = sym(cmd["id"]); qty = cmd["qty"].to_i
      raise "Unknown item" if !GameData::Item.exists?(id)
      if qty >= 0
        $PokemonBag.pbStoreItem(id, qty) ? "Added #{qty}x #{GameData::Item.get(id).name}" : "Bag is full"
      else
        $PokemonBag.pbDeleteItem(id, -qty)
        "Removed #{-qty}x #{GameData::Item.get(id).name}"
      end
    when "heal"
      $Trainer.party.each { |p| p.heal }
      "Party fully healed"
    when "rare_candy_all"
      lvl = cmd["level"].to_i
      $Trainer.party.each { |p| next if p.egg?; p.level = [lvl, p.level].max; p.calc_stats }
      "Party raised to at least level #{lvl}"
    when "repel"
      $PokemonGlobal.repel = cmd["steps"].to_i
      $PokemonGlobal.repel > 0 ? "Repel active: #{$PokemonGlobal.repel} steps" : "Repel off"
    when "speed"
      sp = [[cmd["value"].to_i, 1].max, 5].min
      $GameSpeed = sp
      $frame = 0
      save_speed_setting(sp) rescue nil
      "Game speed #{sp}x"
    when "noclip"
      $game_player.through = !!cmd["on"]
      $game_player.through ? "Walk through walls ON" : "Walk through walls OFF"
    when "next_encounter"
      sp = cmd["species"]
      if sp && !sp.to_s.empty?
        raise "Unknown species" if !GameData::Species.exists?(sp.to_sym)
        @force_species = GameData::Species.get(sp.to_sym).id
      else
        @force_species = nil
      end
      @force_shiny = !!cmd["shiny"]
      (@force_species ? "Wild Pokémon: #{GameData::Species.get(@force_species).name}" : "Wild Pokémon: normal") + (@force_shiny ? " (shiny)" : "")
    when "pkmn_add"
      sp = sym(cmd["species"]); raise "Unknown species" if !GameData::Species.exists?(sp)
      pk = Pokemon.new(sp, [[cmd["level"].to_i, 1].max, GameData::GrowthRate.max_level].min)
      pk.shiny = true if cmd["shiny"]
      pk.calc_stats
      pbAddPokemonSilent(pk) ? "#{pk.name} added" + ($Trainer.party.length >= Settings::MAX_PARTY_SIZE ? " (sent to PC if party was full)" : "") : "No space left"
    when "pkmn_edit"
      pk = $Trainer.party[cmd["slot"].to_i]
      raise "No Pokémon in that slot" if !pk
      f = cmd["fields"] || {}
      if f["species"] && f["species"] != pk.species.to_s
        s = sym(f["species"]); raise "Unknown species" if !GameData::Species.exists?(s)
        data = GameData::Species.get(s)
        pk.species = data.species
        pk.form = data.form if data.form != 0
      end
      pk.form = f["form"].to_i if f.has_key?("form") && f["form"]
      pk.level = [[f["level"].to_i, 1].max, GameData::GrowthRate.max_level].min if f["level"]
      pk.nature = sym(f["nature"]) if f["nature"]
      pk.ability_index = f["ability_index"].to_i if f.has_key?("ability_index")
      pk.instance_variable_set(:@ability, nil) if f.has_key?("ability_index")
      pk.item = (f["item"].to_s.empty? ? nil : sym(f["item"])) if f.has_key?("item")
      pk.shiny = !!f["shiny"] if f.has_key?("shiny")
      pk.happiness = [[f["happiness"].to_i, 0].max, 255].min if f["happiness"]
      pk.name = f["name"] if f["name"] && !f["name"].empty?
      pk.gender = f["gender"].to_i if f.has_key?("gender") && [0, 1].include?(f["gender"].to_i)
      if f["iv"]
        STATS.each_with_index { |s, i| pk.iv[s] = [[f["iv"][i].to_i, 0].max, 31].min }
      end
      if f["ev"]
        STATS.each_with_index { |s, i| pk.ev[s] = [[f["ev"][i].to_i, 0].max, 252].min }
      end
      if f["moves"]
        ids = f["moves"].map { |m| sym(m) }.compact.select { |m| GameData::Move.exists?(m) }.uniq[0, 4]
        if !ids.empty?
          pk.forget_all_moves
          ids.each { |m| pk.learn_move(m) }
        end
      end
      pk.calc_stats
      pk.heal if f["heal"]
      "#{pk.name} updated"
    else
      raise "Unknown command #{op}"
    end
  end

  def process_commands
    return if !File.exist?(CMD_FILE)
    text = File.open(CMD_FILE, "rb") { |f| f.read }
    File.delete(CMD_FILE) rescue nil
    data = parse_json(text.force_encoding("UTF-8")) rescue nil
    cmds = data.is_a?(Array) ? data : [data]
    results = []
    cmds.compact.each do |c|
      begin
        msg = run(c)
        results.push({ "id" => c["id"], "ok" => true, "msg" => msg.to_s })
      rescue Exception => e
        raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
        results.push({ "id" => c["id"], "ok" => false, "msg" => e.message.to_s })
      end
    end
    pbSEPlay("GUI save choice") rescue nil
    DualScreenExport.write_file(RESULT_FILE, DualScreenExport.json({ "t" => Time.now.to_f, "results" => results }))
    DualScreenExport.force
  end

  #-----------------------------------------------------------------------------
  def update
    @frame += 1
    # FPS meter
    now = (System.uptime rescue Time.now.to_f)
    # Rendered frames come from Graphics.frame_count; logic ticks from our own
    # counter (Fire Ash's fast-forward runs several logic ticks per drawn frame).
    @fps_t ||= now
    @fps_fc ||= Graphics.frame_count
    @fps_frames += 1
    if now - @fps_t >= 2.0 && !($game_player && $game_player.moving?)
      dt = now - @fps_t
      drawn = (Graphics.frame_count - @fps_fc) / dt
      DualScreenExport.write_file(PERF_FILE, DualScreenExport.json({
        "fps" => drawn.round(1), "logic" => (@fps_frames / dt).round(1),
        "target" => Graphics.frame_rate, "speed" => ($GameSpeed || 1), "t" => Time.now.to_f }))
      @fps_t = now; @fps_frames = 0; @fps_fc = Graphics.frame_count
    end
    return if @frame % 10 != 0
    return if $game_player && $game_player.moving?
    export_editor if !@editor_done && $Trainer
    process_commands if $Trainer
  rescue Exception => e
    raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
    DualScreenExport.log_error(e)
  end
end

class Scene_Map
  alias __dscheats_update update unless method_defined?(:__dscheats_update)
  def update
    __dscheats_update
    DualScreenCheats.update
  end
end

# "Next wild Pokémon" cheat: replace the species / make it shiny
DualScreenHooks.register("PokemonEncounters", :choose_wild_pokemon) do |enc, orig, args, blk|
  ret = enc.send(orig, *args, &blk)
  sp = DualScreenCheats.force_species
  ret = [sp, ret[1]] if ret && sp
  ret
end

alias __dscheats_pbGenerateWildPokemon pbGenerateWildPokemon unless defined?(__dscheats_pbGenerateWildPokemon)
def pbGenerateWildPokemon(*args)
  pkmn = __dscheats_pbGenerateWildPokemon(*args)
  pkmn.shiny = true if pkmn && DualScreenCheats.force_shiny
  pkmn
end

# merge editor fields into exported party data
module DualScreenExport
  class << self
    alias __cheats_party_info party_info unless method_defined?(:__cheats_party_info)
  end
  def self.party_info
    list = __cheats_party_info
    ($Trainer.party || []).each_with_index do |pk, i|
      next if !list[i]
      list[i].merge!(DualScreenCheats.editor_fields(pk)) rescue nil
    end
    list
  end
end
