-- Dynamic plugin config updates.

return {
  -- table is indexed by the "original" version, and returns the next (1 up)
  -- version.
  -- NOTE: the `conf` parameter is a copy of the configuration, so it can safely
  -- be updated in place and returned.
  
  -- Version 0 is the default if version is missing
  [0] = function(conf)
    -- Take version 0 of the config table, and migrate it to version 1.
    -- Upon errors just call `error()` which will provide the best feedback
    -- including stack trace in the logs.
    
    
    return conf
  end,
  -- add more as you go ...
--  [1] = function(conf)
--    -- Take version 1 of the config table, and migrate it to version 2
--
--    return conf
--  end,

}
