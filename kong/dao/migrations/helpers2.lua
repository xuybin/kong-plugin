local utils = require("kong.tools.utils")
local deep_copy = utils.deep_copy
local load_module_if_exists = utils.load_module_if_exists
local iterator = require("kong.dao.migrations.helpers").plugin_config_iterator
local responses = require("kong.tools.responses")

-- plugin configuration caches
local up2date_conf_cache = setmetatable({}, { __mode = "kv" }) -- weak table to prevent memory leaks
local updated_conf_cache = setmetatable({}, { __mode = "k" }) -- weak table to prevent memory leaks


local _M = {}


-- Creates a 'version' field for in a plugin schema.
-- The current version is automatically determined from the migrations table
local function create_version_field(plugin_name)
  local config_migrations = require("kong.plugins." .. plugin_name .. ".migrations.config")
  local version = 0
  for v, _ in pairs(config_migrations) do -- use pairs, do not assume a list
    if v > version then version = v end
  end
  version = version + 1 -- current version is 1 beyond the last migration

  return {
      type = "number",
      default = version,
      func = function(value)
        return (value == version), "Only version " .. version .. " can be set"
      end,
    }
end


-- Migrate function that will migrate all entries.
-- Will write updated entries back to the DB. Can also provide a dry run.
-- @param dry if thruthy, it will not actually update but perform a dry run
-- @return will not return, but send a response with update statistics
local function api_migrator(dao_factory, plugin_name, dry)
  local migrate = _M.create_config_getter(plugin_name)
  local config_migrations = require("kong.plugins." .. plugin_name .. ".migrations.config")
  local result = {
    current_version = #config_migrations + 1,
    entries = 0, -- total number of entries
    count_per_version = {},
    migrated = 0,
  }
  local count = result.count_per_version

  for ok, config, update in iterator(dao_factory, plugin_name) do
    if not ok then error(config) end

    -- collect statistics
    result.entries = result.entries + 1
    local key = tostring(config.version or 0)
    count[key] = (count[key] or 0) + 1

    -- migrate
    local new_conf = migrate(config)
    if new_conf ~= config then
        -- it was updated
      if dry then
        -- TODO: preferably do full schema validation here

      else
        -- actually write it to the db
        local _, err = update(new_conf)
        if err then error(err) end
        result.migrated = result.migrated + 1
      end
    end
  end

  -- return an ok response with some statistics
  return responses.send_HTTP_OK(result)
end


-- Creates an api function to migrate a plugin.
-- @param plugin_name name of the plugin we're migrating
-- @param dry boolean value indicating whether we're creating a dry-run endpoint
-- @return endpoint function
-- @usage -- a sample pllugin api file could look like this:
-- local create_migrate_endpoint = require("kong.dao.migrations.helpers").create_migrate_endpoint
--
-- return {
--   ["/migrate/" .. plugin_name .. "/"] = {
--     POST = create_migrate_endpoint(plugin_name, false),
--   },
--
--   ["/migrate/" .. plugin_name .. "/dry/"] = {
--     POST = create_migrate_endpoint(plugin_name, true),
--   },
-- }
local function create_migrate_endpoint(plugin_name, dry)
  return function(self, dao_factory)
           return api_migrator(dao_factory, plugin_name, dry)
         end
end


-- Validates plugin-config migrations.
-- Injects a `version` field into the schema.
-- Injects 2 api endpoints in the plugin api.
-- @param plugin_name the name of the plugin
-- @return migrations+current version, nil+error
local function validate_migrations(plugin_name)
  local schema = require("kong.plugins." .. plugin_name .. ".schema")
  schema.fields.version = create_version_field(plugin_name)
  local current_version = schema.fields.version.default

  local success, config_migrations = load_module_if_exists("kong.plugins." ..
                                      plugin_name .. ".migrations.config")
  if not success then
    return nil, "no migrations found at 'kong.plugins." .. plugin_name ..
                       ".migrations.config'"
  end

  if config_migrations[current_version] ~= nil then
    return nil, "There are migrations beyond the current version of " .. plugin_name
  end

  for i = 0, current_version - 1 do
    if not config_migrations[i] then
      return nil, "Migration from version " .. i .. " to version " .. i + 1 ..
                  " is missing for " .. plugin_name
    end
  end

  -- ceate api endpoints, and inject them
  local api, api_name
  api_name = "kong.plugins." .. plugin_name .. ".api"
  success, api = load_module_if_exists(api_name)
  if not success then
    -- no api module found, go create it and insert it into the module cache
    api = {}
    package.loaded[api_name] = api
  end
  api["/migrate/" .. plugin_name .. "/"] = {
    POST = create_migrate_endpoint(plugin_name, false),
  }
  api["/migrate/" .. plugin_name .. "/dry/"] = {
    POST = create_migrate_endpoint(plugin_name, true),
  }

  return config_migrations, current_version
end


-- Gets the updated config version.
-- Updates the provided config table to the latest version, including
-- caching of the results.
-- @param old_conf the provided old configuration
-- @param config_migrations the table with migration functions
-- @param current_version the version of the plugin which we are currently
-- running
-- @return the updated configuration (also stored in the cache)
local function migrate_config(old_conf, config_migrations, current_version)
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


--- Returns a config-getter function.
-- Initializes and validates the migrations.
-- @param plugin_name the name of the plugin to create the getter for
-- @return function that always returns the latest version of a configuration
-- @usage
-- -- at plugin handler module top level initialize (do here because errors
-- -- might be thrown at startup)
-- local get_config = require("kong.dao.migrations.helpers").create_config_getter(plugin_name)
--
-- -- in all your handler functions use the getter to update the config
-- function plugin:access(config)
--   plugin.super.access(self)
--   config = get_config(config)  -- get the updated configuration
--
--   -- your custom code here
--
-- end
function _M.create_config_getter(plugin_name)
  local migrations, current_version = assert(validate_migrations(plugin_name))

  return function(conf)
      return up2date_conf_cache[conf] or
             updated_conf_cache[conf] or
             migrate_config(conf, migrations, current_version)
    end
end

--- Wraps a plugin to make its config versioned.
-- If there is no `kong.plugins.<name>.migrations.config` module then the plugin
-- will remain unaltered (unversioned).
-- @param plugin the plugin table
-- @param plugin_name the plugin_name
-- @return updated plugin table
function _M.wrap_plugin(plugin, plugin_name)
  local success = load_module_if_exists("kong.plugins." ..
                    plugin_name .. ".migrations.config")
  if not success then
    -- there are no dynamic config migrations, so nothing to do
    return plugin
  end

  local config_getter = _M.create_config_getter(plugin_name)
  local methods_to_wrap = {
    "certificate",
    "rewrite",
    "access",
    "header_filter",
    "body_filter",
    "log",
  }

  for _, method_name in ipairs(methods_to_wrap) do
    local old_method = rawget(plugin, method_name)
    if old_method then
      plugin[method_name] = function(self, conf, ...)
        conf = config_getter(conf)
        return old_method(self, conf, ...)
      end
    end
  end

  return plugin
end

return _M
