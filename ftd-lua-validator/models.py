from google.appengine.ext import ndb


def script_key(name):
  """Constructs a Datastore key for a Script entity."""
  return ndb.Key('Script', name)


#class Script(ndb.Model):
#  """A main model representing a script, abstracting version."""
#  name = ndb.StringProperty(indexed=False)
  

class Script(ndb.Model):
  """A main model representing a particular version of a script."""
  version = ndb.StringProperty(indexed=False)  # Human-readable version number.
  # idLine identifies the script. It is presently required to be the first line
  # or the second line following --[[ on the first line (opens a block comment).
  idLine = ndb.StringProperty(indexed=True)
  # The body of the script, excluding configuration.
  body = ndb.StringProperty(indexed=False)
