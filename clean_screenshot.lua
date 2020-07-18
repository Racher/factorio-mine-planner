local d=149
local p={math.floor(game.player.position.x)-d/2,math.floor(game.player.position.y)-d/2}
game.player.surface.destroy_decoratives({p,{p[1]+d,p[2]+d}})
game.take_screenshot{show_entity_info=true,resolution={1920,1080},path='screenshot-tick-'..game.tick..'.png'}
--
game.take_screenshot{show_entity_info=true,resolution={3200,1800},path='screenshot-tick-'..game.tick..'.png'}
local tiles={} for x=1,d do for y=1,d do table.insert(tiles,{name="grass-1",position={p[1]+x,p[2]+y}}) end end game.player.surface.set_tiles(tiles,true,false)
