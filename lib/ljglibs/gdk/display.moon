-- Copyright 2016-2021 The Howl Developers
-- License: MIT (see LICENSE.md at the top-level directory of the distribution)

ffi = require 'ffi'
require 'ljglibs.cdefs.gdk'
core = require 'ljglibs.core'
gobject = require 'ljglibs.gobject'
require 'ljglibs.gdk.clipboard'

C = ffi.C
ref_ptr = gobject.ref_ptr

core.define 'GdkDisplay < GObject', {
  properties: {
    has_pending: => C.gdk_display_has_pending(@) != 0
    clipboard: => C.gdk_display_get_clipboard(@)
    primary_clipboard: => C.gdk_display_get_primary_clipboard(@)
  }

  get_default: -> ref_ptr C.gdk_display_get_default!
  sync: => C.gdk_display_sync @
}
