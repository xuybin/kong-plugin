-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local responses = require("kong.tools.responses")
local iterator = require("kong.dao.migrations.helpers").plugin_config_iterator
local migrate = require("kong.plugins." .. plugin_name .. ".config_migrate")

-- @param dry if thruthy, it will not actually update but perform a dry run
local function migrator(dao_factory, dry)
  local result = {
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

return {
  ["/migrate/" .. plugin_name .. "/"] = {

    POST = function(self, dao_factory)
      return migrator(dao_factory, false)
    end,

  },
  ["/migrate/" .. plugin_name .. "/dry/"] = {

    POST = function(self, dao_factory)
      return migrator(dao_factory, true)
    end,

  },
}