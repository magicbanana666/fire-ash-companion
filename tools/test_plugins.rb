# Smoke test for the plugins outside the game (stubs for Essentials classes).
# Run with:  java -jar jruby-complete.jar tools/test_plugins.rb   (or MRI ruby)
require "tmpdir"
GAME = File.expand_path("../game", __dir__)
Dir.chdir(Dir.mktmpdir)   # the plugins write DualScreen/boot.txt on load

class Scene_Map; def update; end; end
class PokeBattle_Battle; def pbCommandPhase; :original_cmd; end; def pbEndOfBattle; :original_end; end; end
class EventHandler; def +(p); self; end; end
module Events; def self.onMapChange; @h ||= EventHandler.new; end; def self.onMapChange=(v); end; end
class PokemonEncounters; def choose_wild_pokemon(*a); [:PIDGEY, 5]; end; end
def pbGenerateWildPokemon(*a); nil; end
module PluginManager; def self.runPlugins; :plugins_ran; end; end

load File.join(GAME, "DualScreenExport.rb")
load File.join(GAME, "DualScreenCheats.rb")

# --- hooks are installed at load time
$exported = 0
module DualScreenExport; def self.battle_update(b); $exported += 1; end; end
raise "cmd hook" unless PokeBattle_Battle.new.pbCommandPhase == :original_cmd && $exported == 1
raise "encounter hook" unless PokemonEncounters.new.choose_wild_pokemon == [:PIDGEY, 5]

# --- a plugin redefines the methods (like ZUD / v19.1 Hotfixes do) ...
class PokeBattle_Battle; def pbCommandPhase; :zud_cmd; end; end
class PokemonEncounters; def choose_wild_pokemon(*a); [:RATTATA, 3]; end; end
PokeBattle_Battle.new.pbCommandPhase
raise "should be overridden now" unless $exported == 1
# ... and our hooks come back after PluginManager.runPlugins
raise "runPlugins result" unless PluginManager.runPlugins == :plugins_ran
raise "cmd hook after plugins" unless PokeBattle_Battle.new.pbCommandPhase == :zud_cmd && $exported == 2
raise "encounter hook after plugins" unless PokemonEncounters.new.choose_wild_pokemon == [:RATTATA, 3]
# installing twice must not double-wrap
DualScreenHooks.install
PokeBattle_Battle.new.pbCommandPhase
raise "double wrap" unless $exported == 3

# --- JSON
cmd = '[{"id":"a1","op":"pkmn_edit","slot":0,"fields":{"name":"Zap \"Z\"","level":55,"shiny":true,"iv":[31,31,0,31,31,31],"moves":["THUNDERBOLT","SURF"],"item":"","nature":null}},{"op":"money","value":1e3}]'
r = DualScreenCheats.parse_json(cmd)
raise "parse fail" unless r[0]["fields"]["name"] == 'Zap "Z"' && r[0]["fields"]["iv"][2] == 0 && r[0]["fields"]["item"] == "" && r[0]["fields"].key?("nature") && r[1]["value"] == 1000.0
out = DualScreenExport.json({ "a" => [1, 2.5, nil, true, "x\"y\n"], :b => { "c" => :sym } })
raise "json fail" unless out == '{"a":[1,2.5,null,true,"x\"y\n"],"b":{"c":"sym"}}'
puts "ALL OK"
