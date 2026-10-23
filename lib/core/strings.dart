/// Locales ChatHalis ships with. English is the default; Vietnamese is
/// opt-in from Settings.
enum AppLocale { english, vietnamese }

/// All user-facing strings for one locale.
///
/// English and Vietnamese live side by side in the single private
/// constructor so every line stays greppable and nothing gets lost in a
/// translation table.
class Strings {
  Strings._(this.locale);

  final AppLocale locale;

  static final Map<AppLocale, Strings> _cache = <AppLocale, Strings>{};

  /// The strings for [locale], created once and reused.
  static Strings of(AppLocale locale) =>
      _cache[locale] ??= Strings._(locale);

  bool get isVietnamese => locale == AppLocale.vietnamese;
  String _t(String vi, String en) => isVietnamese ? vi : en;

  // ------------------------------------------------------------- identity

  final String appName = 'ChatHalis';
  String get assistantByline => _t('Trợ lý AI', 'AI assistant');

  /// Shown for conversations whose stored title is empty.
  String get untitledConversation =>
      _t('Cuộc trò chuyện mới', 'Untitled chat');

  // ---------------------------------------------------------------- home

  String get homeEmptyTitle => _t('Trợ lý AI của bạn', 'Your AI assistant');
  String get homeEmptySubtitle => _t(
      'Trò chuyện, hỏi đáp và cùng xây dựng ý tưởng với Halis.',
      'Chat, ask questions and build ideas together with Halis.');
  String get homeEmptyCta => _t('Bắt đầu trò chuyện', 'Start chatting');
  String get newChat => _t('Chat mới', 'New chat');
  String get today => _t('Hôm nay', 'Today');
  String get yesterday => _t('Hôm qua', 'Yesterday');
  String get last7Days => _t('7 ngày qua', 'Last 7 days');
  String get earlier => _t('Trước đó', 'Earlier');

  // ---------------------------------------------------------------- chat

  String get inputHint => _t('Nhập tin nhắn cho Halis…', 'Message Halis…');
  String get chatGreetingTitle =>
      _t('Xin chào, tôi là Halis', 'Hi, I\u2019m Halis');
  String get chatGreetingSubtitle =>
      _t('Tôi có thể giúp gì cho bạn hôm nay?', 'How can I help you today?');
  String get thinkingNow => _t('Đang suy nghĩ', 'Thinking');
  String get thoughtFor => _t('Đã suy nghĩ', 'Thought for');
  String get stopped => _t('Đã dừng tạo câu trả lời', 'Stopped generating');
  String get stoppedInline => _t('Đã dừng', 'Stopped');
  String get copy => _t('Sao chép', 'Copy');
  String get copied => _t('Đã sao chép', 'Copied');
  String get regenerate => _t('Tạo lại', 'Regenerate');
  String get retry => _t('Thử lại', 'Retry');
  String get rename => _t('Đổi tên', 'Rename');
  String get chatOptions => _t('Tùy chọn', 'Options');
  String get deleteConversation =>
      _t('Xóa cuộc trò chuyện', 'Delete conversation');
  String get deleteConversationConfirm => _t(
      'Cuộc trò chuyện sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.',
      'This conversation will be permanently deleted. This action cannot be undone.');
  String get cancel => _t('Hủy', 'Cancel');
  String get delete => _t('Xóa', 'Delete');
  String get save => _t('Lưu', 'Save');
  String get renameTitle =>
      _t('Đổi tên cuộc trò chuyện', 'Rename conversation');
  String get renameHint => _t('Tên cuộc trò chuyện', 'Conversation name');

  /// The exact notice shown when a reply is cut off by the 32k output cap.
  String get truncatedNotice => _t(
      'câu trả lời này đã bị ngắt vì đạt giới hạn đầu ra',
      'this reply was cut off because it reached the output limit');

  // ---------------------------------------------------------------- tools

  /// Display name of a tool, shown in the activity chips above an answer.
  String toolName(String tool) => switch (tool) {
        'websearch' => _t('Tìm trên web', 'Web search'),
        'webfetch' => _t('Đọc trang', 'Read page'),
        'datetime' => _t('Thời gian', 'Date & time'),
        _ => tool,
      };

  /// While a tool is still running: `Tìm trên web · thời tiết Huế`.
  String toolDoing(String tool, String label) =>
      label.isEmpty ? toolName(tool) : '${toolName(tool)} · $label';

  // ------------------------------------------------------------ settings

  String get settings => _t('Cài đặt', 'Settings');
  String get aboutSection => _t('Về ứng dụng', 'About');
  String get version => _t('Phiên bản', 'Version');
  String get modelLine => _t('Halis — model được huấn luyện bởi Hieu Louis',
      'Halis — a model trained by Hieu Louis');
  String get engineLabel => _t('Nền tảng', 'Engine');
  final String engineValue = 'Flutter · Dart 3.13';
  String get preferencesSection => _t('Tùy chỉnh', 'Preferences');
  String get appearanceTitle => _t('Giao diện', 'Appearance');
  String get appearanceLight => _t('Sáng', 'Light');
  String get appearanceDark => _t('Tối', 'Dark');
  String get languageTitle => _t('Ngôn ngữ', 'Language');
  final String langEnglish = 'English';
  final String langVietnamese = 'Tiếng Việt';
  String get dataSection => _t('Dữ liệu', 'Data');
  String get dataStoredLocally => _t(
      'Toàn bộ lịch sử trò chuyện được lưu trên máy của bạn.',
      'All your chat history is stored on your device.');
  String get clearAllData => _t('Xóa tất cả dữ liệu', 'Clear all data');
  String get clearAllConfirm => _t(
      'Tất cả cuộc trò chuyện sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.',
      'All conversations will be permanently deleted. This action cannot be undone.');
  String get cleared => _t('Đã xóa toàn bộ dữ liệu', 'All data cleared');
  String get developedBy =>
      _t('Halis · được phát triển bởi Hieu Louis', 'Halis · built by Hieu Louis');

  /// `12 cuộc trò chuyện · 240 tin nhắn` summary in Settings → Data.
  String dataCounts(int conversations, int messages) => _t(
      '$conversations cuộc trò chuyện · $messages tin nhắn',
      '$conversations conversation${conversations == 1 ? '' : 's'} · $messages message${messages == 1 ? '' : 's'}');

  // --------------------------------------------------------------- usage

  String get usageSection => _t('Mức dùng', 'Usage');
  String get usageTitle => _t('Giới hạn chat mỗi giờ', 'Hourly chat limit');
  String usageUsed(int percent) => _t(
      'Bạn đã dùng $percent% giới hạn chat mỗi giờ.',
      'You\u2019ve used $percent% of your hourly chat limit.');
  String get usageLimitReached =>
      _t('Đã đạt giới hạn mỗi giờ.', 'Hourly limit reached.');
  String usageChatAgainIn(Duration remaining) => _t(
      'Bạn có thể chat lại sau ${_countdownVi(remaining)}.',
      'You can chat again in ${_countdownEn(remaining)}.');
  String get usageNote => _t(
      'Giới hạn được đặt lại sau mỗi giờ.',
      'The limit resets every hour.');
  String usageNear(int percent) => _t(
      'Đã dùng $percent% giới hạn chat mỗi giờ',
      '$percent% of your hourly chat limit used');
  String usageLockedStrip(Duration remaining) => _t(
      'Hết giới hạn mỗi giờ · chat lại sau ${_countdownVi(remaining)}',
      'Hourly limit reached · chat resumes in ${_countdownEn(remaining)}');

  // -------------------------------------------------------------- errors

  String get errNetwork => _t(
      'Không kết nối được tới Halis. Kiểm tra kết nối mạng rồi thử lại.',
      'Can\u2019t reach Halis. Check your connection and try again.');
  String get errTimeout =>
      _t('Halis phản hồi quá lâu. Vui lòng thử lại.', 'Halis is taking too long to respond. Please try again.');
  String get errServer => _t(
      'Halis đang bận. Vui lòng thử lại sau ít phút.',
      'Halis is busy right now. Please try again in a few minutes.');
  String get errUnknown =>
      _t('Đã xảy ra lỗi khi kết nối tới Halis.', 'Something went wrong while reaching Halis.');
  String get errRateLimited => _t(
      'Bạn đã dùng hết giới hạn chat trong giờ này. Vui lòng thử lại sau.',
      'You\u2019ve reached your hourly chat limit. Please try again later.');

  // ---------------------------------------------------------- suggestions

  List<String> get suggestions => isVietnamese
      ? const <String>[
          'Giải thích một khái niệm khó theo cách dễ hiểu',
          'Viết một email chuyên nghiệp bằng tiếng Việt',
          'Lên kế hoạch chi tiết cho 3 ngày ở Huế',
          'Viết hàm Dart sắp xếp danh sách đối tượng',
        ]
      : const <String>[
          'Explain a tricky concept in simple terms',
          'Draft a polished, professional email',
          'Plan a detailed 3-day trip to Huế',
          'Write a Dart function that sorts a list of objects',
        ];

  // ----------------------------------------------------------- formatting

  /// Compact weekday label: `T4` / `Wed`.
  String weekdayShort(int weekday) => isVietnamese
      ? const <String>['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][weekday - 1]
      : const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  /// Human-readable thinking time: `12 giây` / `12s`.
  String humanDuration(int ms) {
    if (ms < 1000) return _t('<1 giây', '<1s');
    final seconds = ms ~/ 1000;
    if (seconds < 60) return _t('$seconds giây', '${seconds}s');
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return _t('$minutes phút $rest', '${minutes}m $rest s');
  }

  /// Short countdown for pills and captions: `1 giờ 5 phút` / `1h 05m`.
  String _countdownVi(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes phút';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours giờ' : '$hours giờ $rest phút';
  }

  String _countdownEn(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = (minutes % 60).toString().padLeft(2, '0');
    return '${hours}h ${rest}m';
  }
}
