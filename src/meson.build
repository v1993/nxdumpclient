nxdc_sources = [
  'main.vala',

  'Application.vala',
  'DeviceStatusRow.vala',
  'Window.vala',
  'PreferencesWindow.vala',
  'UsbContext.vala',
  'UsbDeviceClient.vala',
  'UsbDeviceOpener.vala',
  'Utils.vala',

  'widgets/FileRow.vala',
]

nxdc_blueprints = files(
  'DeviceStatusRow.blp',
  'Window.blp',
  'PreferencesWindow.blp',

  'gtk/help-overlay.blp',
  'widgets/FileRow.blp'
)

extra_vala_args = []

nxdc_deps = [
  dependency('glib-2.0', version: '>=2.70'),
  dependency('gio-2.0'),
  dependency('gtk4', version: '>=4.10'),
  dependency('libadwaita-1', version: '>= 1.4'),

  dependency('gusb'),
]

libportal = dependency('libportal', required: get_option('use_libportal'))
libportal_gtk4 = dependency('libportal-gtk4', required: get_option('use_libportal'))

if (libportal.found() and libportal_gtk4.found())
  nxdc_deps += [libportal, libportal_gtk4]
  extra_vala_args += ['-D', 'WITH_LIBPORTAL']
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

# Explicitly depend on blueprints target since valac needs
# .ui files to be present at build time
nxdc_deps += declare_dependency(sources: nxdc_blueprint_tgt)

nxdc_blueprints_build_dir = nxdc_blueprint_tgt.full_path() + '.p'

nxdc_sources += gnome.compile_resources('nxdumpclient-resources',
  'nxdumpclient.gresource.xml',
  c_name: 'nxdumpclient',
  dependencies: [ nxdc_blueprint_tgt ],
  source_dir: [ nxdc_blueprints_build_dir ]
)

executable('nxdumpclient', nxdc_sources, nxdc_blueprint_tgt,
  dependencies: nxdc_deps,
  vala_args: [ '--gresourcesdir', nxdc_blueprints_build_dir, extra_vala_args ],
  install: true,

  c_args: [
    '-DGETTEXT_PACKAGE="nxdumpclient"',
    '-DNXDC_VERSION="@0@"'.format(meson.project_version())
  ],
)
