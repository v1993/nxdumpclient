project('nxdumpclient', ['c', 'vala'],
          version: '1.1.3',
    meson_version: '>= 1.4.0',
  default_options: [ 'warning_level=1', 'werror=false', ],
)

i18n = import('i18n')
gnome = import('gnome')

extra_vapi_dir = meson.current_source_dir() / 'vapi'
add_project_arguments(['--vapidir', extra_vapi_dir], language: 'vala')

subdir('data')
subdir('src')
subdir('po')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
