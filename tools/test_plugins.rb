# Smoke test for the plugins outside the game (stubs for Essentials classes).
class Scene_Map; def update; end; end
class PokeBattle_Battle; def pbCommandPhase; end; def pbEndOfBattle; end; end
class EventHandler; def +(p); self; end; end
module Events; def self.onMapChange; @h ||= EventHandler.new; end; def self.onMapChange=(v); end; end
class PokemonEncounters; def choose_wild_pokemon(*a); [:PIDGEY, 5]; end; end
def pbGenerateWildPokemon(*a); nil; end
require "tmpdir"
GAME = File.expand_path("../game", __dir__)
Dir.chdir(Dir.mktmpdir)   # the plugins write DualScreen/boot.txt on load
load File.join(GAME, "DualScreenExport.rb")
load File.join(GAME, "DualScreenCheats.rb")
raise "encounter hook" unless PokemonEncounters.new.choose_wild_pokemon == [:PIDGEY, 5]

cmd = '[{"id":"a1","op":"pkmn_edit","slot":0,"fields":{"name":"Zap \"Z\"","level":55,"shiny":true,"iv":[31,31,0,31,31,31],"moves":["THUNDERBOLT","SURF"],"item":"","nature":null}},{"op":"money","value":1e3}]'
r = DualScreenCheats.parse_json(cmd)
p r
raise "parse fail" unless r[0]["fields"]["name"] == 'Zap "Z"' && r[0]["fields"]["iv"][2] == 0 && r[0]["fields"]["item"] == "" && r[0]["fields"].key?("nature") && r[1]["value"] == 1000.0
out = DualScreenExport.json({ "a" => [1, 2.5, nil, true, "x\"y\n"], :b => { "c" => :sym } })
puts out
raise "json fail" unless out == '{"a":[1,2.5,null,true,"x\"y\n"],"b":{"c":"sym"}}'
puts "ALL OK"
