#===============================================================================
# WideScreen (Fire Ash, Essentials v19.1)
# Overworld is rendered at 16:9 (682x384) so you see more of the map instead of
# stretching. Menus (bag, party, summary, PC, shops, title/load screen) switch
# back to 4:3 while the screen is faded to black, so no UI ends up misplaced.
#
# Battles use "pillar mode": the screen stays 16:9, the battle itself is drawn
# exactly as designed (512x384) in the centre, and the sides are filled with a
# blurred, darkened copy of the battle background (like emulator bezels).
#
# Disable without touching scripts: create the file  DualScreen/no_widescreen
#===============================================================================
module WideScreen
  WIDE_W   = 682
  NORMAL_W = Settings::SCREEN_WIDTH    # 512
  HEIGHT   = Settings::SCREEN_HEIGHT   # 384

  @depth   = 0
  @enabled = nil
  @pillar  = false
  @suspend = 0
  @fill    = nil

  module_function

  def enabled?
    @enabled = !(File.exist?("DualScreen/no_widescreen") rescue false) if @enabled.nil?
    @enabled
  end

  def log(e)
    Dir.mkdir("DualScreen") rescue nil
    File.open("DualScreen/widescreen_error.txt", "ab") { |f| f.write("[#{Time.now}] #{e.class}: #{e.message}\n#{(e.backtrace || [])[0, 5].join("\n")}\n\n") }
  rescue
  end

  # The real screen width (Graphics.width is faked to 512 in pillar mode)
  def real_width
    Graphics.respond_to?(:__ws_width) ? Graphics.__ws_width : Graphics.width
  end

  def offset
    (real_width - NORMAL_W) / 2
  end

  # true while game code should believe the screen is 512 wide and viewports get centred
  def pillar?
    @pillar && @suspend == 0
  end

  def want_wide?
    enabled? && @depth == 0 && $scene.is_a?(Scene_Map)
  end

  # Switch the internal resolution; keeps the camera on the same spot.
  def apply(w)
    old_w = real_width
    return if old_w == w
    Graphics.resize_screen(w, HEIGHT)
    [:@@viewport0, :@@viewport1, :@@viewport3].each do |cv|
      vp = Spriteset_Map.class_variable_get(cv) rescue nil
      vp.rect.set(0, 0, w, HEIGHT) if vp && !vp.disposed?
    end
    vp2 = Spriteset_Global.class_variable_get(:@@viewport2) rescue nil
    vp2.rect.set(0, 0, w, HEIGHT) if vp2 && !vp2.disposed?
    cx = (w / 2 - Game_Map::TILE_WIDTH / 2) * Game_Map::X_SUBPIXELS
    Game_Player.send(:remove_const, :SCREEN_CENTER_X) if Game_Player.const_defined?(:SCREEN_CENTER_X, false)
    Game_Player.const_set(:SCREEN_CENTER_X, cx)
    if $game_map && $game_map.display_x
      $game_map.display_x -= ((w - old_w) / 2) * Game_Map::X_SUBPIXELS
    end
  rescue Exception => e
    raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
    log(e)
    @enabled = false
  end

  # CustomTilemap shows its buffer starting at 1/4 of the buffer width, so the
  # buffer must be at least 4/3 of the screen width (+ a margin for scrolling).
  def needed_buffer(w, h)
    [((w * 4) / 3.0).ceil + 96, ((h * 4) / 3.0).ceil + 96]
  end

  def update
    apply(want_wide? ? WIDE_W : NORMAL_W)
  end

  # Run a block at 4:3 (menus; screen is black then). Inside a battle (pillar
  # mode) nothing changes: the battle's own menus are already centred.
  def narrow
    return yield if @pillar
    @depth += 1
    apply(NORMAL_W)
    yield
  ensure
    if !@pillar
      @depth -= 1
      update if @depth == 0
    end
  end

  # Run a block with real Graphics.width / unshifted viewports
  def suspend
    @suspend += 1
    yield
  ensure
    @suspend -= 1
  end

  # Battle wrapper
  def pillar(&block)
    return narrow(&block) if !enabled?
    pillar_on(&block)
  end

  def pillar_on
    @depth += 1
    apply(WIDE_W)
    @pillar = true
    yield
  ensure
    @pillar = false
    dispose_fill
    @depth -= 1
    update if @depth == 0
  end

  # Side fill: the battle background scaled to cover the whole 16:9 screen,
  # blurred and darkened, behind the centred battle.
  def make_fill(src)
    dispose_fill
    return if !src || src.disposed? || offset <= 0
    suspend do
      off = offset
      small_w = [src.width / 8, 1].max
      small_h = [src.height / 8, 1].max
      small = Bitmap.new(small_w, small_h)
      small.stretch_blt(Rect.new(0, 0, small_w, small_h), src, Rect.new(0, 0, src.width, src.height))
      big = Bitmap.new(src.width, src.height)
      big.stretch_blt(Rect.new(0, 0, src.width, src.height), small, Rect.new(0, 0, small_w, small_h))
      small.dispose
      begin
        big.blur; big.blur
      rescue
      end
      zoom = [real_width.to_f / src.width, HEIGHT.to_f / src.height].max
      base_x = (real_width - src.width * zoom) / 2
      base_y = (HEIGHT - src.height * zoom) / 2
      # soft dark gradient towards the battle
      eb = Bitmap.new(off, HEIGHT)
      16.times do |i|
        eb.fill_rect(off - 1 - i, 0, 1, HEIGHT, Color.new(0, 0, 0, 170 - i * 10))
      end
      parts = []
      # Two viewports that only cover the side bars. Same z as the battle
      # (99999) and created after the intro's black overlay, so they are drawn
      # above that overlay without ever covering the battle itself.
      [[0, false], [off + NORMAL_W, true]].each do |vx, right|
        vp = Viewport.new(vx, 0, off, HEIGHT)
        vp.z = 99999
        spr = Sprite.new(vp)
        spr.bitmap = big
        spr.zoom_x = zoom
        spr.zoom_y = zoom
        spr.x = base_x - vx
        spr.y = base_y
        spr.tone = Tone.new(-70, -70, -60, 90)
        edge = Sprite.new(vp)
        edge.bitmap = eb
        edge.mirror = right
        parts.push(vp, spr, edge)
      end
      @fill = [parts, [big, eb]]
    end
  rescue Exception => e
    raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
    log(e)
  end

  def dispose_fill
    return if !@fill
    parts, bitmaps = @fill
    parts.reverse.each { |o| o.dispose if o && !o.disposed? }
    bitmaps.each { |b| b.dispose if b && !b.disposed? }
    @fill = nil
  rescue
    @fill = nil
  end
end

#-------------------------------------------------------------------------------
# Pillar mode plumbing: fake Graphics.width, centre new viewports
#-------------------------------------------------------------------------------
module Graphics
  class << self
    alias __ws_width width unless method_defined?(:__ws_width)
    def width
      WideScreen.pillar? ? WideScreen::NORMAL_W : __ws_width
    end
  end
end

class Viewport
  alias __ws_vp_initialize initialize unless method_defined?(:__ws_vp_initialize)
  def initialize(*args)
    if WideScreen.pillar?
      off = WideScreen.offset
      if args.length >= 4
        args = args.dup
        args[0] = args[0] + off
      elsif args[0].is_a?(Rect)
        r = args[0]
        args = [Rect.new(r.x + off, r.y, r.width, r.height)]
      elsif args.empty?
        args = [off, 0, WideScreen::NORMAL_W, WideScreen::HEIGHT]
      end
    end
    __ws_vp_initialize(*args)
  end
end

#-------------------------------------------------------------------------------
# Menus / sub-screens: everything opened through a fade runs at 4:3
#-------------------------------------------------------------------------------
alias __ws_pbFadeOutIn pbFadeOutIn unless defined?(__ws_pbFadeOutIn)
def pbFadeOutIn(*args, &block)
  __ws_pbFadeOutIn(*args) { WideScreen.narrow { block.call if block } }
end

alias __ws_pbFadeOutInWithUpdate pbFadeOutInWithUpdate unless defined?(__ws_pbFadeOutInWithUpdate)
def pbFadeOutInWithUpdate(*args, &block)
  __ws_pbFadeOutInWithUpdate(*args) { WideScreen.narrow { block.call if block } }
end

# Battles: the intro transition plays wide, the battle itself in pillar mode
alias __ws_pbBattleAnimation pbBattleAnimation unless defined?(__ws_pbBattleAnimation)
def pbBattleAnimation(*args, &block)
  __ws_pbBattleAnimation(*args) { WideScreen.pillar { block.call if block } }
end

# The map spritesets are rebuilt at the end of a battle: do that with the real
# screen size, not the faked battle one.
alias __ws_pbSceneStandby pbSceneStandby unless defined?(__ws_pbSceneStandby)
def pbSceneStandby
  $scene.disposeSpritesets if $scene && $scene.is_a?(Scene_Map)
  RPG::Cache.clear
  Graphics.frame_reset
  yield
  WideScreen.suspend { $scene.createSpritesets if $scene && $scene.is_a?(Scene_Map) }
end

class PokeBattle_Scene
  alias __ws_pbCreateBackdropSprites pbCreateBackdropSprites unless method_defined?(:__ws_pbCreateBackdropSprites)
  def pbCreateBackdropSprites
    __ws_pbCreateBackdropSprites
    bg = @sprites["battle_bg"]
    WideScreen.make_fill(bg.bitmap) if bg && bg.bitmap && WideScreen.pillar?
  end
end

#-------------------------------------------------------------------------------
# Overworld
#-------------------------------------------------------------------------------
class Scene_Map
  alias __ws_update update unless method_defined?(:__ws_update)
  def update
    WideScreen.update if !WideScreen.pillar?
    __ws_update
  end
end

# Give every tilemap a drawing buffer big enough for the wide screen from the
# start (before anything is drawn into it).
class CustomTilemap
  alias __ws_initialize initialize unless method_defined?(:__ws_initialize)
  def initialize(*args)
    __ws_initialize(*args)
    begin
      nw, nh = WideScreen.needed_buffer(WideScreen::WIDE_W, WideScreen::HEIGHT)
      if @layer0 && @layer0.bitmap && (@layer0.bitmap.width < nw || @layer0.bitmap.height < nh)
        bw = [nw, @layer0.bitmap.width].max
        bh = [nh, @layer0.bitmap.height].max
        @layer0.bitmap.dispose
        @layer0.bitmap = Bitmap.new(bw, bh)
        @backbuffer.dispose if @backbuffer && !@backbuffer.disposed?
        @backbuffer = Bitmap.new(bw, bh)
      end
    rescue Exception => e
      raise e if e.is_a?(SystemExit) || e.class.name == "Reset"
      WideScreen.log(e)
    end
  end
end

# Title / load screen are 4:3
class Scene_Intro
  alias __ws_main main unless method_defined?(:__ws_main)
  def main
    WideScreen.apply(WideScreen::NORMAL_W)
    __ws_main
  end
end

# Event pictures were placed for a 512 wide screen: centre them.
class Sprite_Picture
  alias __ws_update update unless method_defined?(:__ws_update)
  def update
    __ws_update
    @sprite.x += WideScreen.offset if @sprite && !@sprite.disposed? && WideScreen.offset != 0 && !WideScreen.pillar?
  end
end
