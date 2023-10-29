desktopconf = configuration_data()
desktopconf.set('bindir', get_option('prefix') / get_option('bindir'))

desktop_file_in = configure_file(
          input: 'org.v1993.NXDumpClient.desktop.in.in',
         output: 'org.v1993.NXDumpClient.desktop.in',
  configuration: desktopconf
)

autostart_desktop_file_in = configure_file(
          input: 'org.v1993.NXDumpClient.autostart.desktop.in.in',
         output: 'org.v1993.NXDumpClient.autostart.desktop.in',
  configuration: desktopconf
)

desktop_file = i18n.merge_file(
        input: desktop_file_in,
       output: 'org.v1993.NXDumpClient.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

# Packed into resources
autostart_desktop_file = i18n.merge_file(
        input: autostart_desktop_file_in,
       output: 'org.v1993.NXDumpClient.autostart.desktop',
         type: 'desktop',
       po_dir: '../po',
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'org.v1993.NXDumpClient.appdata.xml.in',
       output: 'org.v1993.NXDumpClient.appdata.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'appdata'
)

appstream_util = find_program('appstream-util', required: false)
if appstream_util.found()
  # Use --nonet to suppress pointless warnings about screenshot
  test('Validate appstream file', appstream_util, args: ['validate', '--nonet', appstream_file])
endif

install_data('org.v1993.NXDumpClient.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate schema file',
       compile_schemas,
       args: ['--strict', '--dry-run', meson.current_source_dir()])
endif

dbusconf = configuration_data()
dbusconf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
          input: 'org.v1993.NXDumpClient.service.in',
         output: 'org.v1993.NXDumpClient.service',
  configuration: dbusconf,
        install: true,
    install_dir: get_option('datadir') / 'dbus-1' / 'services',
)


if get_option('udev_rules') == 'install'
  install_data('71-nxdumptool.rules',
    install_dir: 'lib' / 'udev' / 'rules.d'
  )
endif

install_data(
  'icons/hicolor/scalable/apps/org.v1993.NXDumpClient.svg',
  'icons/hicolor/256x256/apps/org.v1993.NXDumpClient.png',

  install_dir: get_option('datadir'),
  preserve_path: true
)
