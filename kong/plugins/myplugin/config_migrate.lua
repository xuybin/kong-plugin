-- Dynamic plugin updates.

local config_migrations = {

  -- table is indexed by the "original" version, and returns the next (1 up)
  -- version.
  
  -- Version 0 is special, as any config without a `version` field will be
  -- considered version 0
  [0] = function(conf)
    -- Take version 0 of the config table, and migrate it to version 1.
    -- Upon errors just call `error()` which will provide the best feedback
    -- including stack trace in the logs.
    
    
    return conf
  end,
  -- add more as you go ...
--  [1] = function(conf)
--    -- Take version 1 of the config table, and migrate it to version 2
    
--    return conf
--  end,

}

--------------------- Nothing to customize below --------------------------

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- let's validate some stuff before we begin, to catch manual errors
local schema = require("kong.plugins." .. plugin_name .. ".schema")
local current_version = schema.fields.version.default

assert(config_migrations[current_version] == nil, "There are migrations beyond the current version.")

for i = 0, current_version - 1 do
  assert(config_migrations[i], "Migration from version ".. i .." to version " .. i+1 .." is missing")
end

-- actual migration logic
local deep_copy = require("kong.tools.utils").deep_copy
local up2date_conf_cache = setmetatable({}, { __mode = "kv" }) -- weak table to prevent memory leaks
local updated_conf_cache = setmetatable({}, { __mode = "k" }) -- weak table to prevent memory leaks

local function migrate(old_conf)
  local new_conf
  if old_conf.version == current_version then
    -- already up to date, so nothing to migrate
    up2date_conf_cache[old_conf] = old_conf
    return old_conf

  else
    -- let's migrate
    new_conf = deep_copy(old_conf)
    new_conf.version = new_conf.version or 0  -- default to version 0 if absent
    local v = new_conf.version

    while config_migrations[v] do
      local err
      new_conf, err = config_migrations[v](new_conf)
      if not new_conf then
        error("migration " .. v .." failed: " .. (err or
          "migration failed to return the new configuration table"))
      end
      v = v + 1
      new_conf.version = v
    end
  end

  -- we're done, so store in the cache
  updated_conf_cache[old_conf] = new_conf
  return new_conf
end

return function(conf)
    return up2date_conf_cache[conf] or updated_conf_cache[conf] or migrate(conf)
  end
