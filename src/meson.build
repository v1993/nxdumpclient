nxdc_sources = [
  'main.vala',
  'config.vapi',

  'Application.vala',
  'Window.vala',
  'PreferencesDialog.vala',
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
  'PreferencesDialog.blp',
  'UdevRulesDialog.blp',

  'gtk/help-overlay.blp',
  'widgets/DeviceStatusRow.blp',
  'widgets/FileRow.blp',
)

extra_vala_args = []

nxdc_deps = [
  dependency('glib-2.0', version: '>=2.76'),
  dependency('gio-2.0'),
  dependency('gtk4', version: '>=4.13'),
  dependency('libadwaita-1', version: '>= 1.5'),

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

conf_data = configuration_data()

conf_data.set_quoted('NXDC_VERSION',    meson.project_version())
conf_data.set_quoted('NXDC_LOCALE_DIR', get_option('prefix') / get_option('localedir'))
conf_data.set_quoted('NXDC_EXECUTABLE', get_option('prefix') / get_option('bindir') / 'nxdumpclient')

configure_file(
  output: 'config.h',
  configuration: conf_data
)

executable('nxdumpclient', nxdc_sources,
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
