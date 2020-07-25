local function build_main(params)
    local player=params.player
    local surface=player.surface
    local print=player.print
    local force=player.force
    local min=math.min
    local max=math.max
    local ceil=math.ceil
    local floor=math.floor
    local exp=math.exp
    local pow=math.pow
    local sqrt=math.sqrt
    local insert=table.insert
    local function remainder(l,r) return l-floor(l/r)*r end
    local drill_props={consumption=1,pollution=1,productivity=params.prod,speed=1}
    local drill_module_items
    for _,module in pairs(params.modules) do
        for k,v in pairs(game.item_prototypes[module].module_effects) do
            if drill_props[k] then
                drill_props[k]=drill_props[k]+v.bonus
            end
        end
        drill_module_items=drill_module_items or {}
        drill_module_items[module]=(drill_module_items[module] or 0)+1
    end
    drill_props.consumption=max(drill_props.consumption,0.2)
    local ubelt_name=params.belt_name and params.belt_name:gsub('transport','underground')
    local loader_name=params.belt_name and params.belt_name:gsub('transport%-belt','loader')
    local splitter_name=params.belt_name and params.belt_name:gsub('transport%-belt','splitter')
    local drill_name=params.drill_name
    local drill_proto=game.entity_prototypes[drill_name]
    drill_props.speed=drill_props.speed*drill_proto.mining_speed
    drill_props.consumption=drill_props.consumption*drill_proto.max_energy_usage*60
    local supply_area_distance=floor(game.entity_prototypes[params.pole_name].supply_area_distance)
    local max_wire_distance=game.entity_prototypes[params.pole_name].max_wire_distance
    local amount_halflife=params.halflife*drill_props.speed*60
    local drills_per_belt
    local buffer=drill_props.productivity==1 and 0 or 0.026
    local density_iterations=4
    local build_iterations=10
    local function drill_line_speed(drills)
        assert(drills==floor(drills) or drills==0.5,'drill_line_speed '..drills)
        drills=drills/drills_per_belt
        if drill_props.productivity>1 then
            drills=drills*(1-pow(500,drills)/10000)
        end
        return min(drills,1)
    end
    local function measure_cb(proto)
        local cb2=proto.collision_box['right_bottom']
        local cb1=proto.collision_box['left_top']
        local sx=math.ceil(cb2.x-cb1.x)
        local sy=math.ceil(cb2.y-cb1.y)
        local function f(s) return s/2+0.5-math.floor(s/2+0.5) end
        return sx,sy,{f(sx),f(sy)}
    end
    local drill_count_lane_max
    
    local drill_s,drill_sy,drill_off=measure_cb(drill_proto)
    local drill_s_max=floor(drill_s/2)
    local drill_s_min=floor(1-drill_s/2)
    assert(drill_s==drill_sy,'unexpected drill shape')
    local direction=params.direction
    local area_s=params.size
    local area_index_max=area_s*area_s
    local dx_da=(1-floor(direction/4)*2)*(remainder(direction+2,4)/2)
    local dx_db=(floor(direction/4)*2-1)*(remainder(direction,4)/2)
    local dy_da=-dx_db
    local dy_db=dx_da
    local x0=params.position.x-dx_da*floor(area_s/2)
    local y0=params.position.y-dy_da*floor(area_s/2)
    local area_ores={}
    local density_cache={}
    local density_cache2={}
    for i=1,area_index_max do
        density_cache[i]=0
        density_cache2[i]=0
    end
    local build_cache_results={}
    local build_cache_drills={}
    local area_obstacles={}
    local area_drills_candidates={}
    local minin_rad_min=-ceil(drill_proto.mining_drill_radius-drill_off[1]-0.5)
    local minin_rad_max=ceil(drill_proto.mining_drill_radius+drill_off[1]-0.5)
    local mining_s=minin_rad_max-minin_rad_min+1
    local mining_own_tilecount=min(mining_s,drill_s+0.5)*drill_s
    assert(mining_s==ceil(2*drill_proto.mining_drill_radius),'mining_drill_radius')
    local area_mining_indicies={} for a=minin_rad_min,minin_rad_max do for b=minin_rad_min,minin_rad_max do insert(area_mining_indicies,a+b*area_s) end end
    local area_l_min
    local area_l_max
    local area_required_fluid
    local area_l_bmax={}
    local function get_a(i) return remainder(floor(i)-1,area_s) end
    local function get_b(i) return ceil(i/area_s)-1 end
    local function get_drill_out(i)
        assert(floor(area_obstacles[i])==1,'get_drill_out not drill')
        local dir=remainder(area_obstacles[i]*8,8)
        return i+(dir<4 and 1-drill_s_min or drill_s_min-1)
    end
    local function get_l(i)
        assert(floor(area_obstacles[i])==1,'getl')
        return get_a(get_drill_out(i))
    end
    local function get_i(a,b) assert(a>=0 and a<area_s and b>=0 and b<area_s,'geti') return 1+a+b*area_s end
    local function area_index_to_pos(i) local a=get_a(i) local b=get_b(i) return {x0+dx_da*a+dx_db*b,y0+dy_da*a+dy_db*b} end
    local function pos_add(a,b) return {a[1]+b[1],a[2]+b[2]} end
    local function box(p) return {{p[1]-0.4,p[2]-0.4},{p[1]+0.4,p[2]+0.4}} end
    do
        local function find_resource_cat(e) for k,v in pairs(drill_proto.resource_categories) do if v and k==e then return k end end end
        local minable_names={}
        for _,v in pairs(game.entity_prototypes) do
            if v.resource_category and find_resource_cat(v.resource_category) then
                insert(minable_names,v.name)
            end
        end
        local ore_name
        local ore_dist
        for i=1,area_index_max do
            local dx=get_a(i)-area_s/2
            local dy=get_b(i)-4
            local dist=dx*dx+dy*dy
            local o=surface.find_entities_filtered{area=box(area_index_to_pos(i)),name=minable_names}[1]
            if o and get_b(i)>=4 and (not ore_dist or dist<ore_dist) then
                ore_name=o.name
                ore_dist=dist
            end
        end
        assert(ore_name,'no ore')
        local mineable_properties=game.entity_prototypes[ore_name].mineable_properties
        local miningtime=mineable_properties.mining_time
        local productcount=0
        for _,prod in pairs(mineable_properties.products) do
            productcount=productcount+prod.probability*prod.amount
        end
        area_required_fluid=mineable_properties.required_fluid
        drills_per_belt=game.entity_prototypes[params.belt_name].belt_speed*240/drill_props.speed/drill_props.productivity*miningtime/productcount
        drill_count_lane_max=1
        while drill_line_speed(drill_count_lane_max+1)>=drill_line_speed(drill_count_lane_max)+drill_line_speed(0.5) do
            drill_count_lane_max=drill_count_lane_max+1
            assert(drill_count_lane_max<200)
        end
        for i=1,area_index_max do
            local ore=surface.find_entities_filtered{area=box(area_index_to_pos(i)),name=ore_name}[1]
            local anyore=surface.find_entities_filtered{area=box(area_index_to_pos(i)),name=minable_names}[1]
            insert(area_ores,ore and ore.amount or anyore and -1 or 0)
            insert(area_obstacles,surface.can_place_entity{name=params.belt_name,position=area_index_to_pos(i),build_check_type=defines.build_check_type.ghost_place} and 0 or -1)
        end
        local area_l_limits={}
        for da=-1,1,2 do
            local a=floor(area_s/2)-da
            local function merger_obstacle(a)
                for b=0,3 do
                    if area_obstacles[get_i(a,b)]~=0 then
                        return true
                    end
                end
                if area_required_fluid then
                    for _a=a-1-drill_s_max,a+1-drill_s_min do
                        if _a<0 or _a>=area_s or area_obstacles[get_i(_a,4)]~=0 then
                            return true
                        end
                    end
                end
            end
            while a+da>=0 and a+da<area_s and not merger_obstacle(a+da) do
                a=a+da
            end
            insert(area_l_limits,a)
        end
        area_l_min=area_l_limits[1]
        area_l_max=area_l_limits[2]
        assert(area_l_min>=0 and area_l_min<area_s, 'area_l_min'..area_l_min)
        assert(area_l_max>=0 and area_l_max<area_s, 'area_l_max'..area_l_max)
        local function under_bmax(l,bfrom,udist)
            local b=bfrom
            if area_obstacles[get_i(l,bfrom+1)]==0 then
                local function free(_b)
                    return area_obstacles[get_i(l,_b)]==0 and (area_obstacles[get_i(l,_b-1)]==0 or _b+1>=area_s or area_obstacles[get_i(l,_b+1)]==0)
                end
                local function next()
                    if b+1<area_s and free(b+1) then
                        if b+2>=area_s or free(b+2) then
                            b=b+1
                            return true
                        end
                        for _b=b+2,min(b+udist+1,area_s-2) do
                            if free(_b) then
                                b=_b
                                return true
                            end
                        end
                        b=b+1
                        return true
                    end
                end
                while next() do end
            end
            return b
        end
        local max_underground_distance=game.entity_prototypes[ubelt_name].max_underground_distance
        local max_underground_distance_pipe=game.entity_prototypes['pipe-to-ground'].max_underground_distance
        local area_p_bmax={}
        for l=0,area_s-1 do
            insert(area_l_bmax,under_bmax(l,3,max_underground_distance))
            insert(area_p_bmax, area_required_fluid and under_bmax(l,4,max_underground_distance_pipe) or area_s-1)
        end
        for i=1,area_index_max do
            if get_b(i)>=4-drill_s_min+(area_required_fluid and 1 or 0)
             and get_b(i)<area_s-minin_rad_max
             and get_a(i)>=max(area_l_min-drill_s_max-1,-minin_rad_min)
             and get_a(i)<=min(area_l_max-drill_s_min+1,area_s-1-minin_rad_max)
             and (not area_required_fluid or get_b(i)<area_p_bmax[get_a(i)+1]
                                                and (area_obstacles[i+(drill_s_max+1)*area_s] or 0)==0
                                                and (area_obstacles[i+(drill_s_min-1)*area_s] or 0)==0) then
                local ownore=false
                local otherore=false
                local blocked=false
                for id=1,#area_mining_indicies do
                    local di=i+area_mining_indicies[id]
                    ownore=ownore or area_ores[di]>0
                    otherore=otherore or area_ores[di]<0
                end
                for da=drill_s_min,drill_s_max do
                    for db=drill_s_min,drill_s_max do
                        blocked=blocked or area_obstacles[i+da+db*area_s]~=0
                    end
                end
                if ownore and not blocked and not otherore then
                    insert(area_drills_candidates,i)
                end
            end
        end
    end
    local function calc_density(amount)
        local build_dens_max=#area_mining_indicies/mining_own_tilecount
        for ci=1,#area_drills_candidates do
            local i=area_drills_candidates[ci]
            density_cache[i]=0.75
        end
        for _=1,density_iterations do
            for ci=1,#area_drills_candidates do
                local i=area_drills_candidates[ci]
                local acc=0
                for ni=1,#area_mining_indicies do
                    local j=i+area_mining_indicies[ni]
                    acc=acc+area_ores[j]/max(1,min(density_cache[j],build_dens_max))
                end
                acc=min(acc/amount,build_dens_max*1.33)
                density_cache2[i]=density_cache[i]*0.25+acc*0.75
            end
            density_cache,density_cache2=density_cache2,density_cache
        end
        local gapmax=mining_s
        local gapmin=drill_s
        local build_dens_min=mining_s/min(drill_s+0.5,mining_s)
        for ci=1,#area_drills_candidates do
            local i=area_drills_candidates[ci]
            assert(density_cache[i]>0,'density_cache')
            local l=min(1,(density_cache[i]-build_dens_min)/(build_dens_max-build_dens_min))
            density_cache[i]=l>0 and floor(gapmax+l*(gapmin-gapmax)) or 0
        end
        return density_cache
    end
    local function calc_value(amount,speed)
        return speed*(1-exp(-amount/amount_halflife))
    end
    local function pick_initial_amount()
        local distrib={}
        local base=1.1
        for i=1,area_index_max do
            local a=area_ores[i]
            if a>0 then
                local lifelog=floor(math.log(a,base))
                distrib[lifelog]=(distrib[lifelog] or 0)+1
            end
        end
        local loglifes={}
        for loglife,_ in pairs(distrib) do insert(loglifes, -loglife) end
        table.sort(loglifes)
        local prev
        for _,loglife in pairs(loglifes) do
            prev=prev and distrib[-loglife]+prev or distrib[-loglife]
            distrib[-loglife]=prev
        end
        local best_c
        local best_a
        for loglife,count in pairs(distrib) do
            local amount=pow(base,loglife)
            local c=calc_value(amount,count)
            if not best_c or c>best_c then
                best_c=c
                best_a=amount*mining_own_tilecount
            end
        end
        return best_a
    end
    local function drill_l_blocked(l,b)
        if b<2 or b>area_l_bmax[l+1] then
            return true
        end
        for _b=drill_proto.electric_energy_source_prototype and b-2 or b,b do
            if area_obstacles[get_i(l,_b)]~=0 then
                return true
            end
        end
    end
    local function build_drills(amount, limit)
        if not amount or amount<=0 then
            return not limit and 0
        end
        local lane_d = 2*drill_s+1;
        local density=calc_density(amount)
        local best_speed=-1
        for off=0,lane_d-1 do
            while #build_cache_drills>0 do
                build_cache_drills[#build_cache_drills]=nil
            end
            local speed=0
            local carry=0
            for l=area_l_min+off,area_l_max,lane_d do
                for a=l-drill_s_max-1,l-drill_s_min+1,drill_s+1 do
                    if a>=1 and a<area_s-1 then
                        local drill_count_lane=#build_cache_drills
                        local _b=-10
                        local ddir=(l>a and 0.25+2*drill_off[1] or 0.75+2*drill_off[1]*area_s)
                        local ob=ddir>4 and 2*drill_off[1] or 0
                        for b=4-drill_s_min+(area_required_fluid and 1 or 0),area_s-1-drill_s_max do
                            local d=density[get_i(a,b)]
                            if b>=_b and d>=1 and not drill_l_blocked(l,b+ob) and (drill_l_blocked(l,b+ob+1) or density[get_i(a,b+1)]~=d-1) then
                                _b=b+d
                                carry=carry-drill_line_speed(#build_cache_drills-drill_count_lane)
                                insert(build_cache_drills,get_i(a,b)+ddir)
                                carry=carry+drill_line_speed(#build_cache_drills-drill_count_lane)
                                if limit and speed+carry-buffer>=limit-0.0001 then
                                    return build_cache_drills
                                end
                                if #build_cache_drills-drill_count_lane>=drill_count_lane_max then
                                    break
                                end
                            end
                        end
                    end
                end
                if carry>=2+buffer-0.0001 then
                    speed=speed+2
                    carry=carry-2
                end
                carry=min(2,carry)
            end
            speed=speed+carry-buffer+0.0001
            if speed>best_speed then
                best_speed=speed
            end
        end
        return not limit and best_speed
    end
    local function build_drill_speed(amount)
        if build_cache_results[amount] then
            return build_cache_results[amount]
        end
        local speed=build_drills(amount)
        for k,v in pairs(build_cache_results) do
            if k>=amount and v>=speed then
                speed=v
                break
            end
        end
        build_cache_results[amount]=speed
        return speed
    end
    local function calc_value2(amount)
        return calc_value(amount, build_drill_speed(amount))
    end
    local function find_peak()
        local step=1.25
        for i=-build_iterations,0 do
            local peak
            for k,_ in pairs(build_cache_results) do
                if not peak or calc_value2(k)>calc_value2(peak) then
                    peak=k
                end
            end
            local left,right
            for k,v in pairs(build_cache_results) do
                if k<peak then
                    left=left and max(left, k) or k
                elseif k>peak then
                    right=right and min(right, k) or k
                end
            end
            if i==0 then
                if false then
                    print('find_peak    speed: '..(floor(build_drill_speed(peak)*100)/100)..'    amount: '..floor(peak/1000)..'k    value: '..floor(calc_value2(peak)*1000))
                end
                return peak
            end
            local next
            if not peak then
                next=pick_initial_amount()
            elseif not left then
                next=peak/step
            elseif not right then
                next=peak*step
            elseif right*left>peak*peak then
                next=sqrt(peak*right)
            else
                next=sqrt(peak*left)
            end
            build_drill_speed(next)
        end
    end
    local function find_amount(speed)
        if not speed or speed<=0 then
            return 0
        end
        local step=1.25
        for i=-build_iterations,0 do
            local left, right
            for k,v in pairs(build_cache_results) do
                if v>=speed then
                    left=left and max(left,k) or k
                else
                    right=right and min(right,k) or k
                end
            end
            local amount
            if i==0 and left then
                if false then
                    print('find_amount    target: '..speed..' speed: '..(floor(build_drill_speed(left)*100000)/100000)..'    amount'..floor(left/1000)..'k    value: '..floor(calc_value2(left)*1000))
                end
                return left
            elseif not left and not right then
                amount=pick_initial_amount()
            elseif left and not right then
                amount=left*step
            elseif right and not left then
                amount=right/step
            else
                amount=sqrt(left*right)
            end
            build_drill_speed(amount)
        end
    end
    local function find_sweet_amount()
        local peak_amount=find_peak()
        local peak_speed=build_drill_speed(peak_amount)
        if not params.sweetspots then
            return peak_amount, peak_speed
        end
        local left,right
        for _,u in pairs(params.sweetspots) do
            local v=2*u
            if v<=peak_speed then
                left=left and max(left, v) or v
            else
                right=right and min(right, v) or v
            end
        end
        local lefta=left and find_amount(left)
        local righta=right and find_amount(right)
        if righta and (not lefta or calc_value2(lefta)<calc_value2(righta)) then
            left=right
            lefta=righta
        end
        return lefta, left
    end
    local function build_entities(entities)
        if not params.sandbox then
            local stack
            local inv=player.get_main_inventory()
            for _=1,2 do
                for i=1,#inv do
                    local s=inv[i]
                    if s and s.is_blueprint and not s.is_blueprint_setup() then
                        stack=s
                    end
                end
                if stack then
                    break
                end
                inv.insert{name='blueprint'}
            end
            assert(stack,'stack')
            for _,entity in pairs(entities) do
                if drill_module_items and entity.name==drill_name then
                    stack.set_blueprint_entities({{entity_number=1,name=drill_name,position={x=0,y=0},items=drill_module_items}})
                    stack.build_blueprint{surface=surface,position=entity.position,direction=entity.direction,force=force}
                else
                    entity.inner_name=entity.name
                    entity.name='entity-ghost'
                    entity.force=force
                    surface.create_entity(entity)
                end
            end
            stack.clear_blueprint()
        else
            for i=1,area_index_max do
                if area_obstacles[i]==-2 or area_obstacles[i]>0 or true then
                    for _,e in pairs(surface.find_entities(box(area_index_to_pos(i)))) do
                        if e.to_be_deconstructed and e.to_be_deconstructed() then
                            e.destroy{do_cliff_correction=true,raise_destroy=true}
                        end
                    end
                end
            end
            for _,entity in pairs(entities) do
                entity.force=force
                local created_entity=surface.create_entity(entity)
                if entity.name==drill_name then
                    for _,module in pairs(params.modules) do
                        created_entity.insert{name=module}
                    end
                end
            end
        end
    end
    local function make_drills()
        local amount, speed=find_sweet_amount()
        assert(amount and speed, 'could not reach output target')
        local drills=build_drills(amount, speed)
        assert(drills and not tonumber(drills) and #drills>0, 'build drills failed')
        for _,drill in pairs(drills) do
            local dir=remainder(drill*8,8);
            local o=drill_off[1]
            drill=drill-o*(dir>4 and area_s or 1)*2
            for da=drill_s_min,drill_s_max do
                for db=drill_s_min,drill_s_max do
                    area_obstacles[get_i(get_a(drill)+da,get_b(drill)+db)]=-2
                end
            end
        end
        for _,e in pairs(drills) do
            area_obstacles[floor(e)]=1+remainder(e,1)
        end
        return speed
    end
    local function get_lanes()
        local ks={}
        for d=1,area_index_max do
            if floor(area_obstacles[d])==1 then
                ks[get_l(d)]=true
            end
        end
        local lanes={}
        for k,_ in pairs(ks) do
            insert(lanes, k)
        end
        table.sort(lanes)
        local i=1
        while i<=#lanes do
            while i>1 and lanes[i]>lanes[i-1]+7 do
                insert(lanes,i,lanes[i-1]+7)
            end
            i=i+1
        end
        return lanes
    end
    local function get_lines()
        local ks={}
        for d=1,area_index_max do
            if floor(area_obstacles[d])==1 then
                ks[get_a(d)]=true
            end
        end
        local lines={}
        for k,_ in pairs(ks) do
            insert(lines, k)
        end
        table.sort(lines)
        return lines
    end
    local function lane_speed(lane)
        local ls={}
        for d=1,area_index_max do
            if floor(area_obstacles[d])==1 and get_l(d)==lane then
                ls[get_a(d)]=(ls[get_a(d)] or 0)+1
            end
        end
        local speed=0
        for _,v in pairs(ls) do
            speed=speed+drill_line_speed(v)
        end
        return speed
    end
    local function get_boff()
        local function oki(a,b)
            return area_obstacles[get_i(a,b)]==0
        end
        local boffmax=area_s-1
        for i=1,area_index_max do
            if floor(area_obstacles[i])==1 then
                boffmax=min(boffmax,get_b(i))
            end
        end
        local lanes=get_lanes()
        local lines=get_lines()
        for boff=boffmax,0,-1 do
            local function ok()
                for b=boff,boff+(area_required_fluid and 4 or 3) do
                    for a=lanes[1],lanes[#lanes] do
                        if not oki(a,b) then
                            return false
                        end
                    end
                end
                if area_required_fluid then
                    for _,a in pairs(lines) do
                        local v=floor(area_obstacles[get_i(a,boff+5)])
                        local pok=v==-2 or v==0 or v==1
                        if not pok then
                            return false
                        end
                    end
                else
                    for _,a in pairs(lanes) do
                        if not oki(a,boff+4) then
                            return false
                        end
                    end
                end
                return true
            end
            if ok() then
                return boff
            end
        end
        return 0
    end
    local function add_part(i,v)
        if area_obstacles[i]~=0 then
            surface.create_entity{name=params.pole_name,position=area_index_to_pos(i),force=force}
        end
        assert(area_obstacles[i]==0,'attempt to place on taken'..v)
        area_obstacles[i]=v
    end
    local function make_merger_cap(i)
        add_part(i+2*area_s,3)
        add_part(i+area_s,3.25)
        add_part(i+area_s+1,3.5)
        add_part(i+2*area_s+1,3.25)
        add_part(i+2*area_s+2,3.25)
        add_part(i+3*area_s,5)
        add_part(i+3*area_s+1,-2)
    end
    local function make_merger_out(i,left,right)
        add_part(i+2*area_s,3)
        add_part(i+area_s,3.75)
        add_part(i+area_s-1,3.5)
        add_part(i+2*area_s-1,3.75)
        add_part(i+2*area_s-2,3)
        add_part(i+2*area_s-3,3)
        add_part(i+3*area_s-1,5)
        add_part(i+3*area_s,-2)
        add_part(i+area_s-3,5+6/64)
        add_part(i+area_s-2,-2)
        if left then
            add_part(i-3,3.75)
            add_part(i-4,10.75)
            add_part(i-5,-2)
            add_part(i-6,9)
        end
        if right then
            add_part(i-2,10.25)
            add_part(i-1,-2)
            add_part(i,9)
        end
    end
    local function make_merger_ubelt(i)
        add_part(i+3*area_s-3,4.375)
        add_part(i+3*area_s+2,4.25)
    end
    local function make_merger_carry(i)
        local l2=area_obstacles[i+2*area_s-5]>0
        local l3=area_obstacles[i+3*area_s-5]>0
        local r2=area_obstacles[i+2*area_s-3]>0
        local r3=area_obstacles[i+3*area_s-3]>0
        if l2 and l3 or r2 and r3 then
            add_part(i+2*area_s-4,5.25+5/64)
            add_part(i+3*area_s-4,-2)
        else
            if r2 then
                add_part(i+2*area_s-4,3.25)
                if l3 then
                    add_part(i+3*area_s-4,3)
                end
            else
                assert(r3,'no merge carry out')
                add_part(i+3*area_s-4,3.25)
                if l2 then
                    add_part(i+2*area_s-4,3.5)
                end
            end
        end
    end
    local function make_merger_single(left,right)
        for a=left,right-1 do
            add_part(a+3*area_s,3.25)
        end
        add_part(right+3*area_s,10)
        add_part(right+2*area_s,-2)
        add_part(right+1*area_s,9)
    end
    local function make_mergers(speed,boff)
        if drill_s~=3 then
            return
        end
        local lanes=get_lanes()
        assert(#lanes>0,'no lanes')
        if #lanes==1 or speed<=1 then
            make_merger_single(get_i(lanes[1],boff),get_i(lanes[#lanes],boff))
        else
            local carry=0
            for i,l in pairs(lanes) do
                local j=get_i(l,boff)
                local s=lane_speed(l)
                carry=carry+s
                if carry>=2+buffer or i==#lanes then
                    local out2=carry>=1.9999+buffer or i==#lanes and speed>1
                    if out2 then
                        carry=carry-2
                        speed=speed-2
                    end
                    local out1=i==#lanes and speed>0
                    make_merger_out(j,out2,out1)
                elseif s>0 then
                    make_merger_cap(j)
                end
                if i>1 and i<#lanes then
                    make_merger_ubelt(j)
                end
                if i>1 then
                    make_merger_carry(j)
                end
                carry=min(carry,2)
            end
        end
        return boff
    end
    local function make_pipes(boff)
        assert(boff,'pipe boff')
        if not area_required_fluid then
            return
        end
        local lane_d=2*drill_s+1
        local lines={}
        local lanes={}
        local l0
        for i=1,area_index_max do
            if floor(area_obstacles[i])==1 then
                lines[get_a(i)]=max(lines[get_a(i)] or 0, get_b(i))
                l0=remainder(get_l(i),lane_d)
                lanes[get_l(i)]=true
            end
        end
        for k,v in pairs(lines) do
            area_obstacles[get_i(k,4+boff)]=6
            for b=5+boff,v do
                local i=get_i(k,b)
                if area_obstacles[i]==0 and (floor(area_obstacles[i-2*area_s])==1 or floor(area_obstacles[i+2*area_s])==1 or area_obstacles[i-area_s]==6 or area_obstacles[i+area_s]==0) then
                    area_obstacles[i]=6
                end
            end
            for b=5+boff,v do
                local i=get_i(k,b)
                if area_obstacles[i]==6 and area_obstacles[i+area_s]==-1 then
                    area_obstacles[i]=7
                elseif area_obstacles[i]==6 and area_obstacles[i-area_s]==-1 then
                    area_obstacles[i]=7.5
                end
            end
        end
        local as={}
        local ls={}
        for k,_ in pairs(lines) do
            insert(as, k)
        end
        for k,_ in pairs(lanes) do
            insert(ls, k)
        end
        table.sort(as)
        table.sort(ls)
        if #as>0 and #ls>0 then
            for a=as[1],as[#as] do
                local i=get_i(a,4+boff)
                if remainder(a,lane_d)==l0 then
                elseif remainder(a-1,lane_d)==l0 then
                    area_obstacles[i]=7.25
                elseif remainder(a+1,lane_d)==l0 then
                    area_obstacles[i]=7.75
                else
                    area_obstacles[i]=6
                end
            end
            if params.sandbox then
                area_obstacles[get_i(as[1],4+boff)]=8
            end
        end
    end
    local function make_poles_lanes()
        if not drill_proto.electric_energy_source_prototype then
            return
        end
        do
            local mina=area_s-1
            local maxa=0
            local maxb=0
            for d=1,area_index_max do
                if floor(area_obstacles[d])==1 then
                    mina=min(mina,get_a(d)-1)
                    mina=min(mina,get_l(d))
                    maxa=max(maxa,get_a(d)+1)
                    maxa=max(maxa,get_l(d))
                    maxb=max(maxb,get_b(d)+1)
                end
            end
            for i=1,area_index_max do
                if get_a(i)<mina or get_a(i)>maxa or get_b(i)>maxb then
                    area_obstacles[i]=-3
                end
            end
        end
        local lanes={}
        for d=1,area_index_max do
            if floor(area_obstacles[d])==1 then
                lanes[get_l(d)]=true
            end
        end
        for l,_ in pairs(lanes) do
            local lane_drill_bs={}
            for d=1,area_index_max do
                if floor(area_obstacles[d])==1 then
                    if get_l(d)==l then
                        insert(lane_drill_bs, get_b(d))
                    end
                    local i=get_i(get_l(d),get_b(d))
                    assert(area_obstacles[i]==0 or area_obstacles[i]==101,'drill_out_not_free'..area_obstacles[i])
                    area_obstacles[i]=101
                end
            end
            if area_obstacles[get_i(l,4)]==0 then
                area_obstacles[get_i(l,4)]=101
            end
            for b=4,area_s-1 do
                if area_obstacles[get_i(l,b)]<0 then
                    for _b=max(0,b-2),min(area_s-1,b+2) do
                        local i=get_i(l,_b)
                        if area_obstacles[i]==0 then
                            area_obstacles[i]=101
                        end
                    end
                end
            end
            table.sort(lane_drill_bs, function (l,r) return r<l end)
            local prev_pole
            local function wire_ok(j)
                if not prev_pole then
                    return true
                end
                local da=get_a(prev_pole)-get_a(j)
                local db=get_b(prev_pole)-get_b(j)
                return da*da+db*db<=max_wire_distance*max_wire_distance
            end
            for _,b in pairs(lane_drill_bs) do
                if not prev_pole or get_b(prev_pole)-supply_area_distance-1>b then
                    local function findp()
                        for _=1,2 do
                            local bfar=max(0,b-supply_area_distance-1)
                            local bclose=min(b+supply_area_distance+1,area_s-1)
                            if prev_pole then
                                bclose=min(bclose, prev_pole-2)
                            end
                            for off=1,0,-1 do
                                for pb=bfar,bclose,1 do
                                    for pa=l-off,l+off,2 do
                                        if pa>=0 and pa<area_s then
                                            assert(pa>=0 and pa<area_s, 'pa out')
                                            assert(pb>=0 and pb<area_s, 'pb out')
                                            local p=get_i(pa,pb)
                                            if wire_ok(p) and area_obstacles[p]==0 then
                                                area_obstacles[p]=2
                                                return p
                                            end
                                        end
                                    end
                                end
                            end
                            prev_pole=nil
                        end
                    end
                    prev_pole=findp()
                    if not prev_pole then
                        print('failed to pole drill in l '..l..'b '..b)
                    end
                end
            end
        end
        for i=1,area_index_max do
            if area_obstacles[i]==101 then
                area_obstacles[i]=0
            end
        end
    end
    local function make_belts(boff)
        if drill_s~=3 then
            return
        end
        local lanes={}
        for d=1,area_index_max do
            if floor(area_obstacles[d])==1 then
                lanes[get_l(d)]=true
            end
        end
        for l,_ in pairs(lanes) do
            local bmax=0
            for d=1,area_index_max do
                if floor(area_obstacles[d])==1 and get_l(d)==l then
                    bmax=max(bmax, get_b(d))
                end
            end
            for b=4+boff,bmax do
                if b==4+boff or area_obstacles[get_i(l,b)]==0 and (area_obstacles[get_i(l,b-1)]==3 or area_obstacles[get_i(l,b+1)]==0) then
                    area_obstacles[get_i(l,b)]=3
                end
            end
            for b=4+boff,bmax-1 do
                if area_obstacles[get_i(l,b)]==3 and area_obstacles[get_i(l,b+1)]~=3 then
                    area_obstacles[get_i(l,b)]=4
                end
            end
            for b=5+boff,bmax do
                if area_obstacles[get_i(l,b)]==3 and area_obstacles[get_i(l,b-1)]~=3 and area_obstacles[get_i(l,b-1)]~=4.125 then
                    area_obstacles[get_i(l,b)]=4.125
                end
            end
        end
    end
    local function make_poles_conn()
        local poles={}
        for i=1,area_index_max do
            if area_obstacles[i]==2 then
                poles[i]=i
            end
        end
        local reach={}
        for _=1,20 do
            local function dist2(i,j)
                local da=get_a(i)-get_a(j)
                local db=get_b(i)-get_b(j)
                return da*da+db*db
            end
            for i,_ in pairs(poles) do
                local function in_range(j)
                    return dist2(i,j)<=max_wire_distance*max_wire_distance
                end
                for j,q in pairs(poles) do
                    if q<poles[i] and in_range(j) then
                        poles[i]=q
                    end
                end
                for j,q in pairs(poles) do
                    if in_range(j) then
                        for k,r in pairs(poles) do
                            if q==r then
                                poles[k]=poles[i]
                            end
                        end
                    end
                end
            end
            local groups={}
            for _,v in pairs(poles) do
                groups[v]=true
            end
            local g, d
            for _a,_ in pairs(groups) do
                for _b,_ in pairs(groups) do
                    if _a<_b then
                        local _d=area_s*area_s
                        for i,p in pairs(poles) do
                            for j,q in pairs(poles) do
                                if p==_a and q==_b then
                                    _d=min(_d,dist2(i,j))
                                end
                            end
                        end
                        if not d or _d<d then
                            g,d=_a,_d
                        end
                    end
                end
            end
            if not g then
                break
            end
            assert(d>max_wire_distance*max_wire_distance,'touching pole groups')
            for i=1,area_index_max do
                reach[i]=poles[i] and poles[i]==g and 0 or false
            end
            for step=1,30 do
                local function foreach_wire_tile(i, f)
                    for a=max(0,get_a(i)-floor(max_wire_distance)),min(area_s-1,get_a(i)+floor(max_wire_distance)) do
                        for b=max(0,get_b(i)-floor(max_wire_distance)),min(area_s-1,get_b(i)+floor(max_wire_distance)) do
                            local j=get_i(a,b)
                            if j~=i and (area_obstacles[j]==0 or area_obstacles[j]==2) then
                                local d2=dist2(i,j)
                                if d2<=max_wire_distance*max_wire_distance then
                                    f(j,d2/max_wire_distance/max_wire_distance/128)
                                end
                            end
                        end
                    end
                end
                for i=1,area_index_max do
                    if reach[i] and reach[i]>=step-1 and reach[i]<step then
                        foreach_wire_tile(i, function(j,d2)
                            local v=reach[i]+1+d2
                            reach[j]=reach[j] and min(reach[j],v) or v
                        end)
                    end
                end
                local mini
                for i=1,area_index_max do
                    if reach[i] and reach[i]>step and poles[i] and poles[i]~=g and (not mini or reach[i]<reach[mini]) then
                        mini=i
                    end
                end
                if mini then
                    local chain={}
                    for _=1,30 do
                        local next
                        local nextd2
                        foreach_wire_tile(mini,function(j,d2)
                            if reach[j] and reach[j]<reach[mini]-1 and (not next or reach[j]+d2<nextd2) then
                                next=j
                                nextd2=reach[j]+d2
                            end
                        end)
                        if not next then
                            break
                        end
                        insert(chain,next)
                        mini=next
                    end
                    if #chain>0 and reach[chain[#chain]]==0 then
                        chain[#chain]=nil
                        for _,p in pairs(chain) do
                            poles[p]=p
                            area_obstacles[p]=2
                        end
                    else
                        print('failed to connect group '..g)
                    end
                    break
                end
            end
        end
    end
    local function is_powered(i)
        local a=get_a(i)
        local b=get_b(i)
        for _a=max(0,a-supply_area_distance),min(area_s-1,a+supply_area_distance) do
            for _b=max(0,b-supply_area_distance),min(area_s-1,b+supply_area_distance) do
                if area_obstacles[get_i(_a,_b)]==2 then
                    return true
                end
            end
        end
    end
    local function is_interface_clear(i)
        return area_obstacles[i]==0 and area_obstacles[i+1]==0 and area_obstacles[i+area_s]==0 and area_obstacles[i+1+area_s]==0
    end
    local function is_interace_powered(i)
        return is_powered(i) or is_powered(i+1) or is_powered(i+area_s) or is_powered(i+1+area_s)
    end
    local function find_elec_interface_place()
        for loose=0,1 do
            for b=0,area_s-2 do
                for a=0,area_s-2 do
                    local i=get_i(a,b)
                    if (loose==0 and is_interface_clear(i) or loose==1 and area_obstacles[i]<=0) and is_interace_powered(i) then
                        return i
                    end
                end
            end
            print('electric interface position issue: none unobstructed and powered')
        end
        print('electric interface position issue: none unoccupied and powered')
    end
    local function make_elec_interface()
        local i=find_elec_interface_place() or 0
        area_obstacles[i]=11
        local function loose_block(i)
            if area_obstacles[i]==0 then
                area_obstacles[i]=-2
            end
        end
        loose_block(i+1)
        loose_block(i+area_s)
        loose_block(i+1+area_s)
    end
    local speed=make_drills()
    local boff=get_boff()
    make_mergers(speed,boff)
    make_pipes(boff)
    make_poles_lanes()
    make_belts(boff)
    make_poles_conn()
    if params.sandbox and drill_proto.electric_energy_source_prototype then
        make_elec_interface()
    end
    local entities={}
    for i=1,area_index_max do
        local dir=floor(remainder(direction+area_obstacles[i]*8,8))
        local v=floor(area_obstacles[i])
        local subtype=remainder(area_obstacles[i]*4,1)
        if v==1 then
            local off=drill_off for _=1,dir/2 do off={-off[2],off[1]} end
            insert(entities,{name=drill_name,position=pos_add(area_index_to_pos(i),off),direction=dir})
        elseif v==2 then
            insert(entities,{name=params.pole_name,position=area_index_to_pos(i)})
        elseif v==3 then
            insert(entities,{name=params.belt_name,position=area_index_to_pos(i),direction=dir})
        elseif v==4 then
            insert(entities,{name=ubelt_name,position=area_index_to_pos(i),direction=dir,type=(subtype==0 and 'output' or 'input')})
        elseif v==5 then
            local off={0.5,0} for _=1,dir/2 do off={-off[2],off[1]} end
            local splitter={name=splitter_name,position=pos_add(area_index_to_pos(i),off),direction=dir}
            local intype=remainder(subtype*16,4)
            local outtype=floor(remainder(subtype*4,4))
            if intype~=0 then
                splitter.input_priority=(intype==1 and 'left' or 'right')
            end
            if outtype~=0 then
                splitter.output_priority=(outtype==1 and 'left' or 'right')
            end
            insert(entities,splitter)
        elseif v==6 then
            insert(entities,{name='pipe',position=area_index_to_pos(i)})
        elseif v==7 then
            insert(entities,{name='pipe-to-ground',position=area_index_to_pos(i),direction=dir})
        elseif v==8 and params.sandbox then
            insert(entities,{name='infinity-pipe',position=area_index_to_pos(i),infinity_settings={name=area_required_fluid,percentage=1,temperature=25,mode='at-least'}})
        elseif v==9 and params.sandbox then
            insert(entities,{name='infinity-chest',position=area_index_to_pos(i),infinity_settings={remove_unfiltered_items=true}})
        elseif v==10 then
            local off={0,-0.5} for _=1,dir/2 do off={-off[2],off[1]} end
            insert(entities,{name=loader_name,position=pos_add(area_index_to_pos(i),off),direction=dir})
        elseif v==11 and params.sandbox then
            local off={0.5,0.5} for _=1,dir/2 do off={-off[2],off[1]} end
            insert(entities,{name='electric-energy-interface',position=pos_add(area_index_to_pos(i),off),power_production=drill_props.consumption*drills_per_belt*speed})
        end
    end
    build_entities(entities)
end
local function insert_blueprint(player, size)
    local function foreach_item(player,f)
        local inv=player.get_main_inventory() for i=1,#inv do f(inv[i]) end
    end
    local function find_empty_blue(player)
        local b foreach_item(player,function(s) if s and s.is_blueprint and not s.is_blueprint_setup() then b=s end end) return b
    end
    local function find_drill(player)
        local b foreach_item(player, function(s) if s and s.is_blueprint and s.label and string.sub(s.label,1,13)=='mine-planner-' then b=s end end) return b
    end
    local b=find_drill(player)
    if b then
        b.clear_blueprint()
    else
        b=find_empty_blue(player)
        if not b then
            player.get_main_inventory().insert{name='blueprint'}
            b=find_empty_blue(player)
        end
    end
    local tiles={}
    for x=math.ceil(-size/2),math.ceil(size/2-1) do
        for y=-4,size-5 do
            if (x~=0 and x~=-1) or y~=-4 then
                table.insert(tiles,{entity_number=#tiles+1,name=(y<0 and 'hazard-concrete-left' or 'stone-path'),position={x=x,y=y}})
            end
        end
    end
    table.insert(tiles,{entity_number=#tiles+1,name='refined-hazard-concrete-left',position={x=-1,y=-4}})
    table.insert(tiles,{entity_number=#tiles+1,name='refined-hazard-concrete-right',position={x=0,y=-4}})
    b.set_blueprint_tiles(tiles)
    b.blueprint_icons={
        {signal={type='item',name='electric-mining-drill'},index=1},
        {signal={type='item',name='underground-belt'},index=2},
        {signal={type='item',name='splitter'},index=3},
        {signal={type='item',name='loader'},index=4},
    }
    b.label='mine-planner-'..size
    return b
end
local function is_gui_mine(element)
    return script.mod_name=='level' and not element.get_mod() or element.get_mod() and element.get_mod()==script.mod_name
end
local function find_gui(player)
    for _,element in pairs(player.gui.top.children) do
        if is_gui_mine(element) then
            return element
        end
    end
end
local function setup_gui(player)
    local flow=find_gui(player)
    if flow then flow.destroy() end
    flow=player.gui.top.add{type='flow',direction='vertical'}
    flow.add{type='button',caption='Mine Planner'..(script.mod_name=='level' and '*' or '')}
    local options=flow.add{type='frame',direction='vertical',visible=false}
    local opfields=options.add{type='table',column_count=2}
    opfields.add{type='button',caption='planner blueprint',tooltip='Replaces the mine planner blueprint in the player inventory.\nPlace the blueprint trigger the script.'}
    opfields.add{type='textfield',numeric=true,text=67,tooltip='Blueprint size'}
    opfields.add{type='label',caption='mining productivity[10%]',tooltip='Mining productivity from research\nNo research => 0\nMining Productivity 1 => 1'}
    opfields.add{type='textfield',numeric=true,text=(player.force.mining_drill_productivity_bonus or 0)*10}
    opfields.add{type='label',caption='longevity',tooltip='Affect the drill placement script output choice of drill count (initial output vs longevity)'}
    opfields.add{type='slider',minimum_value=-5,maximum_value=5,value=0.00000001,value_step=1}
    opfields.add{type='checkbox',caption='output targets [belt]',tooltip='These number of output belts are targeted',state=false}
    opfields.add{type='textfield',text='0.5,1,1.5,2,3,4,6,8,10,12,14,16'}
    local opelems=options.add{type='table',column_count=7}
    opelems.add{type='choose-elem-button',elem_type='item',item='small-electric-pole',elem_filters={{filter='subgroup',subgroup='energy-pipe-distribution'}}}
    opelems.add{type='choose-elem-button',elem_type='item',item='transport-belt',elem_filters={{filter='subgroup',subgroup='belt'}}}
    opelems.add{type='choose-elem-button',elem_type='entity',entity='electric-mining-drill',elem_filters={{filter='type',type='mining-drill'}}}
    local ceb=opelems.add{type='choose-elem-button',elem_type='item',elem_filters={{filter='type',type='module'}}}
    opelems.add{type='button',caption='->',style=ceb.style.name,tooltip='copy module'}
    opelems.add{type='choose-elem-button',elem_type='item',elem_filters={{filter='type',type='module'}}}
    opelems.add{type='choose-elem-button',elem_type='item',elem_filters={{filter='type',type='module'}}}
    options.add{type='checkbox',caption='cheat_mode',state=player.cheat_mode,tooltip='Create entities instead of ghosts. Add electric interface, infinity pipe, and infinity chests'}
end
local function read_params(player)
    local flow=find_gui(player)
    assert(flow, 'gui not found')
    local options=flow.children[2].children
    local modules={}
    for i,module_but in pairs(options[2].children) do
        if i>3 and module_but.type=='choose-elem-button' and module_but.elem_value then
            table.insert(modules,module_but.elem_value)
        end
    end
    local opcol=options[1].children
    local sweetspots
    if opcol[7].state then
        sweetspots=game.json_to_table('['..opcol[8].text..']')
        assert(sweetspots,'invalid sweetspots')
        table.sort(sweetspots)
    end
    return {
        player=player,
        pole_name=options[2].children[1].elem_value,
        belt_name=options[2].children[2].elem_value,
        drill_name=options[2].children[3].elem_value,
        prod=1+tonumber(opcol[4].text)/10,
        halflife=tonumber(math.pow(2,opcol[6].slider_value)*120),
        sweetspots=sweetspots,
        modules=modules,
        sandbox=options[3].state
    }
end
local function on_build(event, tick, left, right)
    local status,err=pcall(function()
        if event.stack.is_blueprint and event.stack.label and string.sub(event.stack.label,1,13)=='mine-planner-' and game.tick then
            local cleft=event.created_entity.ghost_name=='refined-hazard-concrete-left'
            local cright=event.created_entity.ghost_name=='refined-hazard-concrete-right'
            local position=event.created_entity.position
            event.created_entity.destroy()
            local params
            if cleft or cright then
                local tok=tick and tick==game.tick
                left=tok and left or cleft and position
                right=tok and right or cright and position
                if left and right then
                    params=read_params(game.players[event.player_index])
                    if right.x>left.x then
                        params.direction=0
                    elseif right.y<left.y then
                        params.direction=2
                    elseif right.x<left.x then
                        params.direction=4
                    elseif right.y>left.y then
                        params.direction=6
                    else
                        assert('left right issue')
                    end
                    params.position=math.floor(params.direction/4)==params.direction/4 and right or left
                    params.size=tonumber(string.sub(event.stack.label,14))
                    if false then
                        game.players[event.player_index].print('plan_outpost'..game.table_to_json(params))
                    end
                    build_main(params)
                else
                    tick=game.tick
                    script.on_event(defines.events.on_built_entity,function(event) on_build(event,tick,left,right) end)
                end
            end
        end
    end)
    if not status then
        game.players[event.player_index].print(err)
    end
end
script.on_init(function()
    for _,player in pairs(game.players) do setup_gui(player) end
end)
script.on_event(defines.events.on_player_created,function(event)
    setup_gui(game.players[event.player_index])
end)
script.on_event(defines.events.on_gui_click,function(event)
    local status,err=pcall(function()
        if not is_gui_mine(event.element) then
        elseif string.sub(event.element.caption,1,12)=='Mine Planner' then
            local frame=event.element.parent.children[2]
            frame.visible=frame.visible==false
        elseif event.element.caption=='planner blueprint' then
            insert_blueprint(game.players[event.player_index],tonumber(event.element.parent.children[2].text))
        elseif event.element.caption=='->' then
            local module_buts=event.element.parent.children
            module_buts[6].elem_value=module_buts[4].elem_value
            module_buts[7].elem_value=module_buts[4].elem_value
        end
    end)
    if not status then
        game.players[event.player_index].print(err)
    end
end)
script.on_event(defines.events.on_built_entity,on_build)
local function update_produ_field(event)
    for _,player in pairs(game.players) do
        if event.research.force==player.force then
            local flow=find_gui(player)
            if flow then
                flow.children[2].children[1].children[4].text=(player.force.mining_drill_productivity_bonus or 0)*10
            end
        end
    end
end
script.on_event(defines.events.on_technology_effects_reset,update_produ_field)
script.on_event(defines.events.on_research_finished,update_produ_field)
local function update_cheat_mode(event)
    local player=game.players[event.player_index]
    local flow=find_gui(player)
    if flow then
        flow.children[2].children[3].state=player.cheat_mode
    end
end
script.on_event(defines.events.on_player_cheat_mode_enabled,update_cheat_mode)
script.on_event(defines.events.on_player_cheat_mode_disabled,update_cheat_mode)
if game and game.players then setup_gui(game.player) insert_blueprint(game.player,67) end