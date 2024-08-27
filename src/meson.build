nxdc_sources = []

nxdc_sources_native = [
  'main.vala',
  'config.vapi',

  'Application.vala',
  'Window.vala',
  'PreferencesWindow.vala',
  'UdevRulesDialog.vala',
  'UsbContext.vala',
  'UsbDeviceClient.vala',
  'UsbDeviceOpener.vala',
  'Utils.vala',

  'widgets/DeviceStatusRow.vala',
  'widgets/FileRow.vala',
]

nxdc_blueprints = files(
  'Window.blp',
  'PreferencesWindow.blp',
  'UdevRulesDialog.blp',

  'gtk/help-overlay.blp',
  'widgets/DeviceStatusRow.blp',
  'widgets/FileRow.blp',
)

extra_vala_args = []

nxdc_deps = [
  dependency('glib-2.0', version: '>=2.76'),
  dependency('gio-2.0'),
  dependency('gtk4', version: '>=4.10'),
  dependency('libadwaita-1', version: '>= 1.4'),

  dependency('gusb'),
]

libportal = dependency('libportal', required: get_option('libportal'))
libportal_gtk4 = dependency('libportal-gtk4', required: get_option('libportal'))

if (libportal.found() and libportal_gtk4.found())
  nxdc_deps += [libportal, libportal_gtk4]
  extra_vala_args += ['-D', 'WITH_LIBPORTAL']
endif

if get_option('udev_rules') == 'prompt'
  extra_vala_args += ['-D', 'PROMPT_FOR_UDEV_RULES']
endif

nxdc_blueprint_genlist = generator(
  find_program('blueprint-compiler'),
  output: '@BASENAME@.ui',
  arguments: ['compile', '--output', '@OUTPUT@', '@INPUT@']
).process(
  nxdc_blueprints,
  preserve_path_from: meson.current_source_dir()
)

# Ugly, ugly hack, see https://github.com/mesonbuild/meson/issues/12336
nxdc_blueprint_tgt = custom_target(
  'nxdc-blueprints',
  command: ['true'],
  capture: true,
  output: 'nxdc-blueprints.dummy',
  input: nxdc_blueprint_genlist
)

nxdc_blueprints_build_dir = nxdc_blueprint_tgt.full_path() + '.p'

nxdc_sources += gnome.compile_resources('nxdumpclient-resources',
  'nxdumpclient.gresource.xml',
  c_name: 'nxdumpclient',
  dependencies: [ nxdc_blueprint_tgt, appstream_file, autostart_desktop_file ],
  source_dir: [ nxdc_blueprints_build_dir, '..' / 'data' ]
)

if meson.version() >= '1.4.0'
  nxdc_sources += nxdc_sources_native
else
  # TODO: remove the workaround and bump minimum Meson version when gnome's flatpak
  # runtime updates; runtime 46 is at Meson 1.3.2
  warning(
    'Using workarounds for building with Meson < 1.4.0; this will confuse your IDE.',
    'This is only a problem for developers; users can disregard this warning.',
    'See https://github.com/mesonbuild/meson/pull/12418 for details.'
  )

  extra_vala_args += [ '--gresourcesdir', nxdc_blueprints_build_dir ]

  fs = import('fs')
  foreach file: nxdc_sources_native
    nxdc_sources += custom_target(
      input: file,
      output:  'copied_'+fs.name(file),
      command: [find_program('cat')],
      feed: true,
      capture: true,
      depends: nxdc_blueprint_tgt
    )
  endforeach
endif

conf_data = configuration_data()

conf_data.set_quoted('NXDC_VERSION',    meson.project_version())
conf_data.set_quoted('NXDC_LOCALE_DIR', get_option('prefix') / get_option('localedir'))
conf_data.set_quoted('NXDC_ICONS_PATH', get_option('prefix') / get_option('datadir') / 'icons')
conf_data.set_quoted('NXDC_EXECUTABLE', get_option('prefix') / get_option('bindir') / 'nxdumpclient')

configure_file(
  output: 'config.h',
  configuration: conf_data
)

executable('nxdumpclient', nxdc_sources,
  extra_files: nxdc_sources_native,
  dependencies: nxdc_deps,
  vala_args: extra_vala_args,
  install: true,

  c_args: [
    # These must be defined before GLib includes
    '-DGETTEXT_PACKAGE="nxdumpclient"',
    '-DG_LOG_DOMAIN="nxdumpclient"',
  ],
  win_subsystem: 'windows',
)
