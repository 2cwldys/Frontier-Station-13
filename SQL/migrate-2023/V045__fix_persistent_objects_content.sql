UPDATE ss13_persistent_objects
SET content = '{}'
WHERE content IS NULL
   OR content = ''
   OR JSON_VALID(content) = 0;
