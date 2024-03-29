# Prediction documentation

## Prediction Input

Determines the skillshot input needed for prediction process.  
The "[unit]" type stands for game_object or Vec3 type.

* source - the unit that the skillshot will be launched from **[unit]**
* hitbox - indicates if the unit bounding radius should be included in calculations **[boolean]**
* speed - the skillshot speed in units per second **[number]**
* range - the skillshot range in units **[number]**
* delay - the skillshot initial delay in seconds **[number]**
* radius - the skillshot radius (for non-conic skillshots) **[number]**
* angle - the skillshot angle (for conic skillshots) **[number]**
* collision - determines the collision flags for the skillshot **[table]**:
  * "minion", "ally_hero", "enemy_hero", "wind_wall", "terrain_wall"
* type - the skillshot type: ({"linear", "circular", "conic"})[x] **[string]**

## Prediction Output

Determines the final prediction output for given skillshot input and target.

* cast_pos - the skillshot cast position **[Vec3]**
* pred_pos - the predicted unit position **[Vec3]**
* hit_chance - the calculated skillshot hit chance **[number]**
* hit_count - the area of effect hit count **[number]**
* time_to_hit - the total skillshot arrival time **[number]**

## Hit Chance

* -2 - the unit is unpredictable or invulnerable
* -1 - the skillshot is colliding the units on path
* 0 - the predicted position is out of the skillshot range
* (0.01 - 0.99) - the solution has been found for given range
* 1 - the unit is immobile or skillshot will land for sure
* 2 - the unit is dashing or blinking

## API

* **_calc_aa_damage_to_minion(game_object source, game_object minion)_ [number]**  
  Calculates the auto-attack damage to minion target and returns it.

* **_get_aoe_prediction(prediction_input input, game_object unit)_ [prediction_output]**  
  Returns the area of effect prediction output for given input and unit.

* **_get_aoe_position(prediction_input input, table<unit> points, unit star)_ [{position, hit_count}]**  
  Calculates the area of effect position for given input and table of targets.  
  You can use a third optional parameter which defines a "star target" that is **always included** in output.

* **_get_collision(prediction_input input, Vec3 end_pos, game_object exclude)_ [table<unit>]**  
  Returns the list of the units that the skillshot will hit before reaching the set end position.

* **_get_position_after(game_object unit, number delta, boolean skip_latency)_ [Vec3]**  
  Returns the position where the unit will be after a set time. When the **skip_latency**  
  parameter is not used, it will increase the set time due to the latency and server tick.

* **_get_health_prediction(game_object unit, number delta)_ [number]**  
  Returns the unit health after a set time. Health prediction supports enemy minions only.

* **_get_lane_clear_health_prediction(game_object unit, number delta)_ [number]**  
  Returns the unit health after a set time assuming that the past auto-attacks are periodic.

* **_get_prediction(prediction_input input, game_object unit)_ [prediction_output]**  
  Returns the general prediction output for given input and unit.

* **_get_immobile_duration(game_object unit)_ [number]**  
  Returns the duration of the unit's immobilility.

* **_get_invisible_duration(game_object unit)_ [number]**  
  Returns the duration of the unit's invisibility or fog of war state.

* **_get_invulnerable_duration(game_object unit)_ [number]**  
  Returns the duration of the unit's invulnerability (supports champions only)

* **_get_movement_speed(game_object unit)_ [number]**  
  Returns the unit's movement speed (also supports dashing speed).

* **_get_waypoints(game_object unit)_ [table<Vec3>]**  
  Returns the current moving path of the unit (also works in fog of war state).

* **_is_loaded()_**  
  Indicates if prediction library has been loaded successfully.

* **_set_collision_buffer(number buffer)_**  
  Sets the additional collision buffer for **get_collision** calculations.

* **_set_internal_delay(number delay)_**  
  Sets the internal delay for prediction calculations.

## Example (Ezreal Q)

```lua
local myHero = game.local_player
local pred = _G.Prediction

local input = {
    source = myHero,
    speed = 2000, range = 1150,
    delay = 0.25, radius = 60,
    collision = {"minion", "wind_wall"},
    type = "linear", hitbox = true
}

local function on_tick()
    if spellbook:can_cast(SLOT_Q) or not
        pred:is_loaded() then return end
    for _, unit in ipairs(game.players) do
        if unit.is_valid and unit.is_enemy then
            local output = pred:get_prediction(input, unit)
            local inv = pred:get_invisible_duration(unit)
            if output.hit_chance > 0.5 and inv < 0.125 then
                local p = output.cast_pos
                spellbook:cast_spell(SLOT_Q, 0.25, p.x, p.y, p.z)
            end
        end
    end
end

client:set_event_callback("on_tick", on_tick)
```
