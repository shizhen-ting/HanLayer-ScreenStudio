app = '/tmp/汉层 HanLayer.app'
files = [app]
symlinks = {'Applications': '/Applications'}
background = 'background.tiff'
import os as _os
_here = _os.path.dirname(_os.path.abspath(__file__))
icon = _os.path.join(_here, '..', 'app-src', 'icon-hanlayer.icns')
window_rect = ((240, 200), (660, 420))
icon_size = 160
text_size = 12
icon_locations = {
    '汉层 HanLayer.app': (168, 188),
    'Applications': (492, 188),
}
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
