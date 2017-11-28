local SCHEMA_VERSION = 1

return {
  no_consumer = false, -- this plugin is available on APIs as well as on Consumers,
  fields = {
    version = {
      -- do not update this field, only update the constant `SCHEMA_VERSION` above
      type = "number",
      default = SCHEMA_VERSION,
      func = function(value)
        return (value == SCHEMA_VERSION), "Only version " ..
               tostring(SCHEMA_VERSION) .. " can be set"
      end,
    },
    
    -- Describe your plugin's configuration's schema here.
    
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    -- perform any custom verification
    return true
  end
}
