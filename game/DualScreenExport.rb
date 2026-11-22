#===============================================================================
# Dual Screen Export (Fire Ash Companion)
# Writes the current game state to DualScreen/state.json (and the static
# world data to DualScreen/static.json) so a companion app on a second screen
# can show the region map, route encounters and party.
# Everything is wrapped in rescue blocks: a failure here never stops the game.
#===============================================================================
module DualScreenExport
  DIR          = "DualScreen"
  STATE_FILE   = DIR + "/state.json"
  STATIC_FILE  = DIR + "/static.json"
  ERROR_FILE   = DIR + "/error.txt"
  CHECK_FRAMES = 15            # how often (in frames) to look for changes

  @frame        = 0
  @last_sig     = nil
  @static_done  = false
  @errors       = 0

  module_function

  #-----------------------------------------------------------------------------
  # Minimal JSON writer (mkxp has no json extension)
  #-----------------------------------------------------------------------------
  def json(obj)
    case obj
    when nil then "null"
    when true then "true"
    when false then "false"
    when Integer then obj.to_s
    when Float then (obj.finite? ? obj.round(3).to_s : "0")
    when Symbol then json_str(obj.to_s)
    when String then json_str(obj)
    when Array then "[" + obj.map { |v| json(v) }.join(",") + "]"
    when Hash then "{" + obj.map { |k, v| json_str(k.to_s) + ":" + json(v) }.join(",") + "}"
    else json_str(obj.to_s)
    end
  end

  def json_str(s)
    s = s.to_s.dup
    s.force_encoding("UTF-8") rescue nil
    out = s.gsub(/[\\"\u0000-\u001f]/) do |c|
      case c
      when "\\" then "\\\\"
      when "\"" then "\\\""
      when "\n" then "\\n"
      when "\r" then "\\r"
      when "\t" then "\\t"
      else format("\\u%04x", c.ord)
      end
    end
    "\"" + out + "\""
  end

  #-----------------------------------------------------------------------------
  def write_file(path, text)
    Dir.mkdir(DIR) rescue nil
    tmp = path + ".tmp"
    File.open(tmp, "wb") { |f| f.write(text) }
    begin
      File.delete(path) if File.exist?(path)
      File.rename(tmp, path)
    rescue
      File.open(path, "wb") { |f| f.write(text) }
    end
  end

  def log_error(e)
    @errors += 1
    return if @errors > 20
    Dir.mkdir(DIR) rescue nil
    File.open(ERROR_FILE, "ab") do |f|
      f.write("[#{Time.now}] #{e.class}: #{e.message}\n#{(e.backtrace || [])[0, 6].join("\n")}\n\n")
    end
  rescue
  end

  #-----------------------------------------------------------------------------
  # Helpers
  #-----------------------------------------------------------------------------
  def species_info(sp)
    data = GameData::Species.get(sp)
    icon = GameData::Species.icon_filename(data.species, data.form) rescue nil
    return {
      "id"    => data.id.to_s,
      "base"  => data.species.to_s,
      "form"  => data.form,
      "name"  => data.name,
      "fname" => (data.form_name rescue nil),
      "num"   => (data.id_number rescue 0),
      "types" => [data.type1, data.type2].compact.uniq.map { |t| t.to_s },
      "icon"  => icon
    }
  end

  def encounter_table(types_hash)
    ret = {}
    types_hash.each do |type, list|
      next if !list || list.empty?
      agg = {}
      order = []
      total = 0
      list.each do |slot|
        prob, sp, minl, maxl = slot
        maxl ||= minl
        total += prob
        key = sp.to_s
        if !agg[key]
          agg[key] = { "sp" => key, "chance" => 0, "min" => minl, "max" => maxl }
          order.push(key)
        end
        agg[key]["chance"] += prob
        agg[key]["min"] = minl if minl < agg[key]["min"]
        agg[key]["max"] = maxl if maxl > agg[key]["max"]
      end
      rows = order.map { |k| agg[k] }
      rows.each { |r| r["chance"] = (total > 0) ? (r["chance"] * 100.0 / total).round : 0 }
      ret[type.to_s] = rows.sort_by { |r| -r["chance"] }
    end
    ret
  end

  def town_map_pos(map_id)
    md = GameData::MapMetadata.try_get(map_id) rescue nil
    return nil if !md || !md.town_map_position
    pos = md.town_map_position
    x = pos[1]; y = pos[2]
    if map_id == $game_map.map_id
      size = md.town_map_size
      if size && size[0] && size[0] > 0
        sqw = size[0]
        sqh = (size[1].length * 1.0 / size[0]).ceil
        x += ($game_player.x * sqw / $game_map.width).floor if sqw > 1
        y += ($game_player.y * sqh / $game_map.height).floor if sqh > 1
      end
    end
    { "region" => pos[0], "x" => x, "y" => y }
  end

  #-----------------------------------------------------------------------------
  # Static data: region maps, map positions, all encounters (once per session)
  #-----------------------------------------------------------------------------
  def export_static
    regions = []
    (pbLoadTownMapData || []).each_with_index do |r, i|
      next regions.push(nil) if !r
      rname = pbGetMessage(MessageTypes::RegionNames, i) rescue nil
      rname = r[0] if nil_or_empty?(rname)
      points = (r[2] || []).map do |p|
        pname = (pbGetMessageFromHash(MessageTypes::PlaceNames, p[2]) rescue nil) || p[2]
        poi   = (p[3] && !p[3].to_s.empty?) ? ((pbGetMessageFromHash(MessageTypes::PlaceDescriptions, p[3]) rescue nil) || p[3]) : nil
        { "x" => p[0], "y" => p[1], "name" => pname, "poi" => poi, "switch" => p[7] }
      end
      regions.push({ "name" => rname, "image" => "Graphics/Pictures/" + r[1].to_s, "points" => points })
    end
    maps = {}
    GameData::MapMetadata.each do |md|
      next if !md.town_map_position
      maps[md.id.to_s] = {
        "name" => (pbGetMapNameFromId(md.id) rescue md.id.to_s),
        "pos"  => md.town_map_position,
        "size" => md.town_map_size
      }
    end
    version = ($PokemonGlobal.encounter_version rescue 0) || 0
    encounters = {}
    species = {}
    GameData::Encounter.each_of_version(version) do |enc|
      tbl = encounter_table(enc.types)
      next if tbl.empty?
      encounters[enc.map.to_s] = {
        "name"  => (pbGetMapNameFromId(enc.map) rescue enc.map.to_s),
        "types" => tbl
      }
      maps[enc.map.to_s] ||= { "name" => encounters[enc.map.to_s]["name"], "pos" => nil, "size" => nil }
      tbl.each_value { |rows| rows.each { |r| species[r["sp"]] ||= (species_info(r["sp"]) rescue { "id" => r["sp"], "name" => r["sp"] }) } }
    end
    player_icon = (GameData::TrainerType.player_map_icon_filename($Trainer.trainer_type) rescue nil)
    write_file(STATIC_FILE, json({
      "version"     => 1,
      "game"        => (System.game_title rescue "Fire Ash"),
      "square"      => 16,
      "regions"     => regions,
      "maps"        => maps,
      "encounters"  => encounters,
      "species"     => species,
      "player_icon" => player_icon,
      "generated"   => Time.now.to_i
    }))
    @static_done = true
  end

  #-----------------------------------------------------------------------------
  # Dynamic state
  #-----------------------------------------------------------------------------
  def active_types
    enc = $PokemonEncounters
    return [] if !enc
    time = pbGetTimeNow
    [:Land, :Cave, :Water].map { |b| enc.find_valid_encounter_type_for_time(b, time) rescue nil }.compact.map(&:to_s)
  end

  CATEGORIES = ["Physical", "Special", "Status"]

  def move_info(m, pp = nil, total = nil)
    data = GameData::Move.get(m.id) rescue nil
    {
      "name"  => (m.name rescue m.id.to_s),
      "type"  => (m.type.to_s rescue ""),
      "cat"   => (CATEGORIES[(data ? data.category : m.category)] rescue ""),
      "power" => (data ? data.base_damage : 0),
      "acc"   => (data ? data.accuracy : 0),
      "pp"    => (pp || m.pp rescue 0),
      "maxpp" => (total || m.total_pp rescue 0),
      "desc"  => (data ? data.description : "")
    }
  end

  def item_name(id)
    return nil if !id
    GameData::Item.get(id).name rescue id.to_s
  end

  def bag_info
    bag = $PokemonBag
    return [] if !bag
    names = PokemonBag.pocketNames rescue []
    out = []
    (bag.pockets || []).each_with_index do |pocket, i|
      next if i == 0 || !pocket
      items = pocket.map do |slot|
        id, qty = slot
        { "name" => item_name(id), "qty" => qty, "icon" => (GameData::Item.icon_filename(id) rescue nil) }
      end
      out.push({ "name" => names[i] || "Pocket #{i}", "items" => items })
    end
    out
  end

  def type_chart(types)
    weak = {}; resist = {}; immune = []
    GameData::Type.each do |t|
      next if (t.pseudo_type rescue false)
      v = Effectiveness.calculate(t.id, *types[0, 3]) rescue next
      mult = v / Effectiveness::NORMAL_EFFECTIVE.to_f
      if mult == 0 then immune.push(t.id.to_s)
      elsif mult > 1 then weak[t.id.to_s] = mult
      elsif mult < 1 then resist[t.id.to_s] = mult
      end
    end
    { "weak" => weak, "resist" => resist, "immune" => immune }
  end

  def battle_info(battle)
    return nil if !battle
    battlers = battle.instance_variable_get(:@battlers) || []
    foes = []; mine = []
    battlers.each do |b|
      next if !b || (b.fainted? rescue true)
      types = (b.pbTypes(true) rescue [b.type1, b.type2]).compact.uniq
      sp = (b.displaySpecies rescue b.species)
      entry = {
        "index"  => b.index,
        "name"   => (b.name rescue sp.to_s),
        "level"  => b.level,
        "hp"     => b.hp,
        "totalhp"=> (b.totalhp rescue 1),
        "status" => (b.status ? b.status.to_s : "NONE"),
        "types"  => types.map(&:to_s),
        "icon"   => (GameData::Species.icon_filename(sp, (b.displayForm rescue b.form), 0, (b.shiny? rescue false)) rescue nil),
        "owned"  => (($Trainer.pokedex.owned?(sp)) rescue false)
      }
      if b.opposes?
        entry["chart"] = type_chart(types)
        foes.push(entry)
      else
        entry["moves"] = (b.moves || []).map do |m|
          mi = move_info(m, m.pp, (m.total_pp rescue nil))
          mi["vs"] = {}
          battlers.each do |f|
            next if !f || !f.opposes? || (f.fainted? rescue true)
            ftypes = (f.pbTypes(true) rescue [f.type1, f.type2]).compact.uniq
            mt = (m.pbCalcType(b) rescue m.type)
            v = Effectiveness.calculate(mt, *ftypes[0, 3]) rescue nil
            mi["vs"][f.index.to_s] = v ? (v / Effectiveness::NORMAL_EFFECTIVE.to_f) : 1
          end
          mi
        end
        mine.push(entry)
      end
    end
    { "wild" => (battle.wildBattle? rescue false), "foes" => foes, "mine" => mine }
  end

  def party_info
    ($Trainer.party || []).map do |pkmn|
      {
        "moves"   => (pkmn.moves || []).map { |m| move_info(m) },
        "ability" => (pkmn.ability ? pkmn.ability.name : nil rescue nil),
        "nature"  => (pkmn.nature ? pkmn.nature.name : nil rescue nil),
        "stats"   => ([pkmn.totalhp, pkmn.attack, pkmn.defense, pkmn.spatk, pkmn.spdef, pkmn.speed] rescue []),
        "exp"     => (begin
                        gr = GameData::GrowthRate.get(pkmn.growth_rate)
                        lo = gr.minimum_exp_for_level(pkmn.level)
                        hi = gr.minimum_exp_for_level([pkmn.level + 1, GameData::GrowthRate.max_level].min)
                        hi > lo ? ((pkmn.exp - lo) * 100.0 / (hi - lo)).round : 100
                      rescue
                        nil
                      end),
        "name"    => pkmn.name,
        "species" => (GameData::Species.get(pkmn.species).name rescue pkmn.species.to_s),
        "level"   => pkmn.level,
        "hp"      => pkmn.hp,
        "totalhp" => pkmn.totalhp,
        "status"  => (pkmn.status ? pkmn.status.to_s : "NONE"),
        "shiny"   => (pkmn.shiny? rescue false),
        "egg"     => (pkmn.egg? rescue false),
        "item"    => (pkmn.item ? (GameData::Item.get(pkmn.item).name rescue pkmn.item.to_s) : nil),
        "types"   => ([pkmn.type1, pkmn.type2].compact.uniq.map(&:to_s) rescue []),
        "icon"    => (GameData::Species.icon_filename_from_pokemon(pkmn) rescue nil)
      }
    end
  end

  def dex_lists
    seen = []; owned = []
    dex = $Trainer.pokedex
    GameData::Species.each do |sp|
      next if sp.form != 0
      s = sp.species
      owned.push(s.to_s) if dex.owned?(s)
      seen.push(s.to_s) if dex.seen?(s)
    end
    [seen, owned]
  end

  def signature
    p = $game_player
    party = ($Trainer.party || []).map { |k| [k.species, k.level, k.hp, k.status, k.egg?, k.item, k.exp, (k.moves || []).map { |m| [m.id, m.pp] }] }
    bag = ($PokemonBag.pockets.hash rescue 0)
    dex = $Trainer.pokedex
    [ $game_map.map_id, p.x, p.y, ($PokemonGlobal.surfing rescue false), party,
      (dex.seen_count rescue 0), (dex.owned_count rescue 0), active_types,
      ($Trainer.badges.hash rescue 0), ($Trainer.money rescue 0), bag ].hash
  end

  def export_state(battle = nil)
    seen, owned = dex_lists
    map_id = $game_map.map_id
    write_file(STATE_FILE, json({
      "t"        => Time.now.to_f,
      "battle"   => battle_info(battle),
      "bag"      => bag_info,
      "map"      => {
        "id"   => map_id,
        "name" => (pbGetMapNameFromId(map_id) rescue $game_map.name),
        "pos"  => town_map_pos(map_id),
        "x"    => $game_player.x, "y" => $game_player.y,
        "w"    => $game_map.width, "h" => $game_map.height
      },
      "surfing"  => ($PokemonGlobal.surfing rescue false),
      "active"   => active_types,
      "night"    => (PBDayNight.isNight? rescue false),
      "party"    => party_info,
      "seen"     => seen,
      "owned"    => owned,
      "player"   => {
        "name"   => $Trainer.name,
        "badges" => ($Trainer.badge_count rescue 0),
        "badge_list" => (($Trainer.badges || []).map { |b| b ? true : false } rescue []),
        "money"  => ($Trainer.money rescue 0),
        "region" => (pbGetCurrentRegion rescue 0)
      }
    }))
  end

  #-----------------------------------------------------------------------------
  def update
    return if !$game_map || !$game_player || !$Trainer
    @frame += 1
    return if @frame % CHECK_FRAMES != 0
    export_static if !@static_done
    sig = signature
    return if sig == @last_sig
    @last_sig = sig
    export_state
  rescue Exception => e
    raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
    log_error(e)
    @last_sig = sig rescue nil
  end

  def force
    @last_sig = nil
  end

  def battle_update(battle)
    return if !$Trainer
    export_state(battle)
    @last_sig = nil
  rescue Exception => e
    raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
    log_error(e)
  end
end

#===============================================================================
# Hooks that survive plugins.
# Essentials loads PluginScripts.rxdata *after* Scripts.rxdata, and plugins
# (e.g. ZUD, v19.1 Hotfixes) redefine some battle/encounter methods, which
# would silently remove a normal alias-based hook. Hooks registered here are
# installed immediately and re-installed after PluginManager.runPlugins.
#===============================================================================
module DualScreenHooks
  @hooks = []        # [class name, method, body]
  @installed = {}    # [class name, method] => UnboundMethod of our wrapper
  @n = 0

  # body receives (object, original method name, args, block)
  def self.register(klass_name, meth, &body)
    @hooks.push([klass_name, meth, body])
    install
  end

  def self.install
    @hooks.each do |klass_name, meth, body|
      begin
        klass = Object.const_get(klass_name) rescue next
        next if !klass.method_defined?(meth) && !klass.private_method_defined?(meth)
        key = [klass_name, meth]
        next if @installed[key] && klass.instance_method(meth) == @installed[key]
        @n += 1
        orig = :"__dshook_#{meth}_#{@n}"
        klass.send(:alias_method, orig, meth)
        klass.send(:define_method, meth) { |*args, &blk| body.call(self, orig, args, blk) }
        @installed[key] = klass.instance_method(meth)
      rescue Exception => e
        raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
        DualScreenExport.log_error(e)
      end
    end
  end
end

module PluginManager
  class << self
    if method_defined?(:runPlugins) && !method_defined?(:__dshook_runPlugins)
      alias __dshook_runPlugins runPlugins
      def runPlugins(*args, &blk)
        ret = __dshook_runPlugins(*args, &blk)
        DualScreenHooks.install
        ret
      end
    end
  end
end

# Battle: export at the start of every round (command phase) and when it ends.
DualScreenHooks.register("PokeBattle_Battle", :pbCommandPhase) do |battle, orig, args, blk|
  DualScreenExport.battle_update(battle)
  battle.send(orig, *args, &blk)
end

DualScreenHooks.register("PokeBattle_Battle", :pbEndOfBattle) do |battle, orig, args, blk|
  ret = battle.send(orig, *args, &blk)
  DualScreenExport.force
  ret
end

class Scene_Map
  alias __dualscreen_update update unless method_defined?(:__dualscreen_update)
  def update
    __dualscreen_update
    DualScreenExport.update
  end
end

Events.onMapChange += proc { |_sender, _e| DualScreenExport.force }

# Signal "Fire Ash is starting" right away (the companion auto-start waits for this).
# Also remove data from the previous session so the companion doesn't show a
# stale team/badges on the title screen, and drop unprocessed cheat commands.
begin
  Dir.mkdir(DualScreenExport::DIR) rescue nil
  ["state.json", "cmd.json", "cmd_result.json", "perf.json"].each do |f|
    path = DualScreenExport::DIR + "/" + f
    File.delete(path) if File.exist?(path) rescue nil
  end
  File.open(DualScreenExport::DIR + "/boot.txt", "wb") { |f| f.write(Time.now.to_i.to_s) }
rescue
end
