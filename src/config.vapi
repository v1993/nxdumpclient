// lower_case_cprefix is required even if unused in practice
[CCode (cprefix = "NXDC_", lower_case_cprefix = "nxdc_", cheader_filename = "config.h")]
namespace BuildConfig {
	public const string VERSION;
	public const string LOCALE_DIR;
	public const string ICONS_PATH;
	public const string EXECUTABLE;
}
