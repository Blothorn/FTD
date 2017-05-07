from google.appengine.ext import ndb
import webapp2

from models import (script_key, Script)
from validate import validate


class Main(webapp2.RequestHandler):
  def get(self):
    self.redirect('/static/html/index.html')


class ValidateBp(webapp2.RequestHandler):
  def post(self):
    blueprint = self.request.get('bp')
    if validate(blueprint):
      self.redirect('/static/html/success.html')
    else:
      self.redirect('/static/html/failure.html')


class UploadScript(webapp2.RequestHandler):
  def post(self):
    name = self.request.get('name')
    script = Script(parent=script_key(name))
    script.version = self.request.get('version')
    script.idLine = self.request.get('id-line').replace('"', '\\"')
    script.body = self.request.get('body').replace('"', '\\"')
    script.put()

    self.redirect('/')


app = webapp2.WSGIApplication([
    ('/', Main),
    ('/validate-bp', ValidateBp),
    ('/upload-script', UploadScript),
  ], debug=True)
