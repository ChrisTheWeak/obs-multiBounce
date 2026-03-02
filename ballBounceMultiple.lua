--[[
Bounces objects around a screen. 
v1.0

To Do List
-- Automatic refresh when new scene items are added 
-- Support for rotation and mirroring 
-- Support for mulitple bounding box options 
-- Improve movement detection 
-- Finetune gravity and other constants 
-- Add sliding scale options for more constants 
-- Make the UI less awful 
-- Add more options aside from all align to center
-- Make "start_on_scene_change" make sense in the current version (holdover from previous code)
-- Make tutorial for how to use 
-- Install code comments (Current code comments are leftovers from previous project)
-- Add README to GitHub
-- Learn Plug-Ins so that half of the features I want to actually add can even work 

Based on obs-bounce v1.3 - https://github.com/insin/obs-bounce
MIT Licensed
]]--

local obs = obslua
local bit = require('bit')

local items = {}
local enabled_sources = {}
local next = next
local bounceOnMove = true
local scriptSettings = nil

--- Hotkeys
local hotkey_id_toggleBounce = obs.OBS_INVALID_HOTKEY_ID
local hotkey_id_manualBounce = obs.OBS_INVALID_HOTKEY_ID
local hotkey_id_centerAlign = obs.OBS_INVALID_HOTKEY_ID
local hotkey_id_bounceOnMove = obs.OBS_INVALID_HOTKEY_ID

-- Shared config
--- if true bouncing will auto start and stop on scene change
local start_on_scene_change = true
--- true when the scene item is being moved
local active = false
--- width of the scene the scene item belongs to
local scene_width = nil
--- height of the scene the scene item belongs to
local scene_height = nil

-- Throw & Bounce
--- Range of initial horizontal velocity
local throw_speed_x = 100
--- Range of initial vertical velocity
local throw_speed_y = 50
-- physics config
local gravity = 0.98*900
local air_drag = 0.99
local ground_friction = 0.95
local elasticity = 0.8

--- find the named scene item in the current scene
--- store its original position and color_add, to be restored when we stop bouncing it
local function find_scene_item()
   items = {}
   local source = obs.obs_frontend_get_current_scene()
   if not source then return end

   local video_info = obs.obs_video_info()
   obs.obs_get_video_info(video_info)


   scene_width  = video_info.base_width
   scene_height = video_info.base_height

   local scene = obs.obs_scene_from_source(source)
   for name in pairs(enabled_sources) do
      local scene_itemi = obs.obs_scene_find_source(scene, name)
      obs.obs_sceneitem_set_bounds_type(scene_itemi, obs.OBS_BOUNDS_NONE)
      items[name] = {
         scene_item = scene_itemi,
         velocity_x = 0,
         velocity_y = 0,
         previous_pos = nil,
         original_pos = nil,
         wait = 1,
         held = false
      }
      items[name]["original_pos"] = get_scene_item_pos(scene_itemi)
   end
   obs.obs_source_release(source)
end

function script_description()
   return 'Applies Physics to sources in a scene'
end

function script_properties()
   local props = obs.obs_properties_create()
   
   obs.obs_properties_add_int_slider(props, 'throw_speed_x', 'Max Throw Speed (X):', 1, 200, 1)
   obs.obs_properties_add_int_slider(props, 'throw_speed_y', 'Max Throw Speed (Y):', 1, 100, 1)
   obs.obs_properties_add_bool(props, 'start_on_scene_change', 'Auto start/stop on scene change')
   obs.obs_properties_add_button(props, 'button', 'Toggle', toggle)
   obs.obs_properties_add_button(props, 'bounceOnMove', 'Objects Bounce After Moving Toggle', bounceOnMoveToggle)
   obs.obs_properties_add_button(props, 'buttonBounce', 'Bounce', manualBounce)
   obs.obs_properties_add_button(props, 'originSetter', 'Set All To Center', originSetter)

   for _, source_name in ipairs(get_source_names()) do
      obs.obs_properties_add_bool(props, source_name, source_name)
   end
   return props
end

function script_defaults(settings)
   obs.obs_data_set_default_int(settings, 'throw_speed_x', throw_speed_x)
   obs.obs_data_set_default_int(settings, 'throw_speed_y', throw_speed_y)
end

function script_update(settings)
   enabled_sources={}
   scriptSettings = settings
   for _, source_name in ipairs(get_source_names()) do
      if obs.obs_data_get_bool(settings, tostring(source_name)) then
         enabled_sources[source_name] = true
      end
   end

   for name in pairs(items) do
      if not enabled_sources[name] then 
         obs.obs_sceneitem_set_pos(items[name]['scene_item'], items[name]['original_pos'])
         items[name] = nil
      end
   end

   local source = obs.obs_frontend_get_current_scene()
   local scene = obs.obs_scene_from_source(source)
   for name in pairs(enabled_sources) do 
      if not items[name] then
         local scene_itemi = obs.obs_scene_find_source(scene, name)
         if scene_itemi then
            obs.obs_sceneitem_set_bounds_type(scene_itemi, obs.OBS_BOUNDS_NONE)
            items[name] = {
               scene_item = scene_itemi,
               velocity_x = math.random(-throw_speed_x, throw_speed_x)*30,
               velocity_y = -math.random(throw_speed_y)*30,
               previous_pos = nil,
               original_pos = get_scene_item_pos(scene_itemi), 
               wait = 1,
               held = false
            }
         end
      end
   end
   obs.obs_source_release(source)

   throw_speed_x = obs.obs_data_get_int(settings, 'throw_speed_x')
   throw_speed_y = obs.obs_data_get_int(settings, 'throw_speed_y')
   start_on_scene_change = obs.obs_data_get_bool(settings, 'start_on_scene_change')
end

function script_load(settings)
   hotkey_id_toggleBounce = obs.obs_hotkey_register_frontend('toggle_bounce', 'Toggle Bounce', toggle)
   hotkey_id_manualBounce = obs.obs_hotkey_register_frontend('manualBounce', 'Manual Bounce', manualBounce)
   hotkey_id_centerAlign = obs.obs_hotkey_register_frontend('centerAlign', 'Align Sources At Center', originSetter)
   hotkey_id_bounceOnMove = obs.obs_hotkey_register_frontend('bounceOnMove', 'Bounce on Move', bounceOnMoveToggle)

   local toggleBounce_save_array = obs.obs_data_get_array(settings, 'toggle_bounce')
   obs.obs_hotkey_load(hotkey_id_toggleBounce, toggleBounce_save_array)
   obs.obs_data_array_release(toggleBounce_save_array)

   local manualBounce_save_array = obs.obs_data_get_array(settings, 'manualBounce')
   obs.obs_hotkey_load(hotkey_id_manualBounce, manualBounce_save_array)
   obs.obs_data_array_release(manualBounce_save_array)

   local centerAlign_save_array = obs.obs_data_get_array(settings, 'centerAlign')
   obs.obs_hotkey_load(hotkey_id_centerAlign, centerAlign_save_array)
   obs.obs_data_array_release(centerAlign_save_array)

   local bounceOnMove_save_array = obs.obs_data_get_array(settings, 'bounceOnMove')
   obs.obs_hotkey_load(hotkey_id_bounceOnMove, bounceOnMove_save_array)
   obs.obs_data_array_release(bounceOnMove_save_array)

   obs.obs_frontend_add_event_callback(on_event)
   scriptSettings = settings
end

function script_unload()
   stop()
end

function on_event(event)
   if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
      if start_on_scene_change then
         scene_changed()
      end
   end
   if event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
      if active then
         stop()
      end
   end
   if event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then 
      script_update(scriptSettings)
   end
end

function script_save(settings)
   local toggleBounce_save_array = obs.obs_hotkey_save(hotkey_id_toggleBounce)
   obs.obs_data_set_array(settings, 'toggle_bounce', toggleBounce_save_array)
   obs.obs_data_array_release(toggleBounce_save_array)

   local manualBounce_save_array = obs.obs_hotkey_save(hotkey_id_manualBounce)
   obs.obs_data_set_array(settings, 'manualBounce', manualBounce_save_array)
   obs.obs_data_array_release(manualBounce_save_array)

   local centerAlign_save_array = obs.obs_hotkey_save(hotkey_id_centerAlign)
   obs.obs_data_set_array(settings, 'centerAlign', centerAlign_save_array)
   obs.obs_data_array_release(centerAlign_save_array)

   local bounceOnMove_save_array = obs.obs_hotkey_save(hotkey_id_bounceOnMove)
   obs.obs_data_set_array(settings, 'bounceOnMove', bounceOnMove_save_array)
   obs.obs_data_array_release(bounceOnMove_save_array)
end

-- Experimental Change
function script_tick(seconds)
   if not active then return end
   for name, body in pairs(items) do
      update_body(body, seconds)
   end
end

function update_body(body, dt)
   if not body then return end

   local current_pos = get_scene_item_pos(body.scene_item)

   if not body.previous_pos then
      body.previous_pos = current_pos
      return
   end

   local dx = current_pos.x - body.previous_pos.x
   local dy = current_pos.y - body.previous_pos.y

   local moved = (math.abs(dx) > 0.01 or math.abs(dy) > 0.01)

   -- Detect manual movement immediately
   if moved then
      body.velocity_x = 0
      body.velocity_y = 0
      body.previous_pos = current_pos
      body.held=true
      body.wait=1
      return
   end

   if body.held then
      if not bounceOnMove then return end
      if body.wait < 0 then
         body.velocity_x = math.random(-throw_speed_x, throw_speed_x)*30
         body.velocity_y = -math.random(throw_speed_y)*30
         body.held = false
      else
         body.wait = body.wait - dt
      end
      return
   end

   throw_scene_item(body,dt)

   body.previous_pos = get_scene_item_pos(body.scene_item)
end

--- get a list of source names, sorted alphabetically
function get_source_names()
   local sources = obs.obs_enum_sources()
   local source_names = {}
   if sources then
      for _, source in ipairs(sources) do
         -- exclude Desktop Audio and Mic/Aux by their capabilities
         local capability_flags = obs.obs_source_get_output_flags(source)
         if bit.band(capability_flags, obs.OBS_SOURCE_DO_NOT_SELF_MONITOR) == 0 and
            capability_flags ~= bit.bor(obs.OBS_SOURCE_AUDIO, obs.OBS_SOURCE_DO_NOT_DUPLICATE) then
            table.insert(source_names, obs.obs_source_get_name(source))
         end
      end
   end
   obs.source_list_release(sources)
   table.sort(source_names, function(a, b)
      return string.lower(a) < string.lower(b)
   end)
   return source_names
end

--- convenience wrapper for getting a scene item's crop in a single statement
function get_scene_item_crop(scene_item_body)
   local crop = obs.obs_sceneitem_crop()
   obs.obs_sceneitem_get_crop(scene_item_body, crop)
   return crop
end

--- convenience wrapper for getting a scene item's pos in a single statement
function get_scene_item_pos(scene_item_body)
   local pos = obs.vec2()
   obs.obs_sceneitem_get_pos(scene_item_body, pos)
   return pos
end

--- convenience wrapper for getting a scene item's scale in a single statement
function get_scene_item_scale(scene_item_body)
   local scale = obs.vec2()
   obs.obs_sceneitem_get_scale(scene_item_body, scale)
   return scale
end

function get_scene_item_dimensions(scene_item_body)
   local pos = get_scene_item_pos(scene_item_body)
   local scale = get_scene_item_scale(scene_item_body)
   local crop = get_scene_item_crop(scene_item_body)
   local source = obs.obs_sceneitem_get_source(scene_item_body)
   -- displayed dimensions need to account for cropping and scaling
   local width = round((obs.obs_source_get_width(source) - crop.left - crop.right) * scale.x)
   local height = round((obs.obs_source_get_height(source) - crop.top - crop.bottom) * scale.y)
   return pos, width, height
end

--- throw a scene item and let it come to rest with physics
function throw_scene_item(body, dt)

   local pos, width, height = get_scene_item_dimensions(body.scene_item)
   local next_pos = obs.vec2()

   next_pos.x = pos.x + body.velocity_x*dt
   next_pos.y = pos.y + body.velocity_y*dt

   -- bounce off the bottom
   if next_pos.y >= scene_height - height then
      next_pos.y = scene_height - height
      body.velocity_y = -(body.velocity_y * elasticity)
   end

   -- bounce off the sides
   if next_pos.x >= scene_width - width or next_pos.x <= 0 then
      if next_pos.x <= 0 then
         next_pos.x = 0
      else
         next_pos.x = scene_width - width
      end
      body.velocity_x = -(body.velocity_x * elasticity)
   end

   if body.velocity_y ~= 0 or (scene_height - height) > 0 then
      body.velocity_y = body.velocity_y + gravity*dt
      body.velocity_y = body.velocity_y * (air_drag^(dt*30))
   end
   body.velocity_x = body.velocity_x * (air_drag^(dt*30))

   if next_pos.y == scene_height - height then
      body.velocity_x = body.velocity_x * (ground_friction^(dt*30))
   end

   obs.obs_sceneitem_set_pos(body.scene_item, next_pos)
end

function manualBounce(pressed)
   if not pressed then return end
   if next(items)~=nil and active then
      for _, body in pairs(items) do
         body.held = false
         body.wait = 1
         body.velocity_x = math.random(-throw_speed_x, throw_speed_x)*30
         body.velocity_y = -math.random(throw_speed_y)*30
      end
   elseif not active then
      toggle(true)
   end

end

--- start bouncing the scene item
function start()
   if next(items)~=nil then
      active = true
      for _, body in pairs(items) do
         body.velocity_x = math.random(-throw_speed_x, throw_speed_x)*30
         body.velocity_y = -math.random(throw_speed_y)*30
      end
   end
end

--- stop bouncing the scene item, restoring its original position
function stop()
   if active then
      active = false
      for _, body in pairs(items) do 
         body.velocity_x = 0
         body.velocity_y = 0
         if body.scene_item then
            obs.obs_sceneitem_set_pos(body.scene_item, body.original_pos)
         end
      end
      if next(items)~=nil then
         items = {}
      end
   end
end

--- toggle bouncing the scene item
function toggle(pressed)
   if not pressed then return end
   if active then
      stop()
   else
      find_scene_item()
      start()
   end
end

--- on scene change, stops bouncing the scene item if it's currently bouncing. If the scene item is
--- present in the current scene, starts bouncing it.
function scene_changed()
   if active then
      stop()
   end
   find_scene_item()
   if next(items)~=nil then
      start()
   end
end

--- round a number to the nearest integer
function round(n)
   return math.floor(n + 0.5)
end

function originSetter(pressed)
   if not pressed then return end
   find_scene_item()
   for _, body in pairs(items) do 
      obs.obs_sceneitem_set_bounds_type(body.scene_item, obs.OBS_BOUNDS_NONE)
      local _, width, height = get_scene_item_dimensions(body.scene_item)
      local pos = obs.vec2()
      pos.x = scene_width * 0.5 - width*0.5
      pos.y = scene_height * 0.5 - height*0.5
      obs.obs_sceneitem_set_pos(body.scene_item, pos)
      local pos = get_scene_item_pos(body.scene_item)
      body.original_pos = pos
   end
      stop()
end

function bounceOnMoveToggle(pressed)
   if not pressed then return end 
   bounceOnMove = not bounceOnMove
end