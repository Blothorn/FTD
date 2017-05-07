from google.appengine.ext import ndb
import logging
import re

from models import Script

STRING_DATA_PATTERN = re.compile(r'"BlockStringData":\["(.*?[^\\])"')

def validate(blueprint):
  for data in re.findall(STRING_DATA_PATTERN, blueprint):
    if not data.find('update'):
      # Not a Lua block, or not doing anything.
      continue
    lines = data.split('\\r\\n')

    idLine = lines[1] if lines[0] == '--[[' else lines[0]
    canonical = Script.query(Script.idLine == idLine).get()
    if canonical == None:
      logging.info('No matching script.')
      return False;
    
    canonicalLines = re.split('\r?\n', canonical.body)
    try:
      start = lines.index(canonicalLines[0])
      for i, canonicalLine in enumerate(canonicalLines):
        line = lines[start + i]
        if line != canonicalLine:
          logging.info('"{}" does not match "{}".'
                       .format(line, canonicalLine))
          return False
      return lines[start:] == canonicalLines
    except ValueError:
      logging.info('Body not found (looking for "{}").'
                   .format(canonicalLines[0]))
      return False;

  return True;
                        
