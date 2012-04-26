import Gtk from lgi
import Delegator from vilu.aux.moon

class Window extends Delegator
  new: (properties) =>
    super Gtk.Window properties

  add_view: (view) =>
    mt = getmetatable view
    gobject = if mt and mt.__to_gobject then mt.__to_gobject(view) else view
    self\add(gobject)

return Window
