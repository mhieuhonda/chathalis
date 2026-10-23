/// Every user-facing string in ChatHalis, in one place.
abstract final class HalisStrings {
  static const String appName = 'ChatHalis';
  static const String assistantName = 'Halis';
  static const String assistantByline = 'Trợ lý AI';

  // Home
  static const String homeEmptyTitle = 'Trợ lý AI của bạn';
  static const String homeEmptySubtitle =
      'Trò chuyện, hỏi đáp và cùng xây dựng ý tưởng với Halis.';
  static const String homeEmptyCta = 'Bắt đầu trò chuyện';
  static const String newChat = 'Chat mới';
  static const String today = 'Hôm nay';
  static const String yesterday = 'Hôm qua';
  static const String last7Days = '7 ngày qua';
  static const String earlier = 'Trước đó';

  // Chat
  static const String inputHint = 'Nhập tin nhắn cho Halis…';
  static const String chatGreetingTitle = 'Xin chào, tôi là Halis';
  static const String chatGreetingSubtitle = 'Tôi có thể giúp gì cho bạn hôm nay?';
  static const String thinkingNow = 'Đang suy nghĩ';
  static const String thoughtFor = 'Đã suy nghĩ';
  static const String stopped = 'Đã dừng tạo câu trả lời';
  static const String copy = 'Sao chép';
  static const String copied = 'Đã sao chép';
  static const String regenerate = 'Tạo lại';
  static const String retry = 'Thử lại';
  static const String rename = 'Đổi tên';
  static const String deleteConversation = 'Xóa cuộc trò chuyện';
  static const String deleteConversationConfirm =
      'Cuộc trò chuyện sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.';
  static const String cancel = 'Hủy';
  static const String delete = 'Xóa';
  static const String save = 'Lưu';
  static const String renameTitle = 'Đổi tên cuộc trò chuyện';
  static const String renameHint = 'Tên cuộc trò chuyện';

  /// The exact notice shown when a reply is cut off by the 32k output cap.
  static const String truncatedNotice =
      'câu trả lời này đã bị ngắt vì đạt giới hạn đầu ra';

  // Settings
  static const String settings = 'Cài đặt';
  static const String aboutSection = 'Về ứng dụng';
  static const String version = 'Phiên bản';
  static const String developedWith = 'Xây dựng bằng Flutter';
  static const String modelLine = 'Halis — model được huấn luyện bởi Hieu Louis';
  static const String dataSection = 'Dữ liệu';
  static const String dataStoredLocally =
      'Toàn bộ lịch sử trò chuyện được lưu trên máy của bạn.';
  static const String clearAllData = 'Xóa tất cả dữ liệu';
  static const String clearAllConfirm =
      'Tất cả cuộc trò chuyện sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.';
  static const String cleared = 'Đã xóa toàn bộ dữ liệu';

  // Errors
  static const String errNetwork =
      'Không kết nối được tới Halis. Kiểm tra kết nối mạng rồi thử lại.';
  static const String errTimeout = 'Halis phản hồi quá lâu. Vui lòng thử lại.';
  static const String errServer = 'Halis đang bận. Vui lòng thử lại sau ít phút.';
  static const String errUnknown = 'Đã xảy ra lỗi khi kết nối tới Halis.';

  // Suggestions on a fresh chat
  static const List<String> suggestions = <String>[
    'Giải thích một khái niệm khó theo cách dễ hiểu',
    'Viết một email chuyên nghiệp bằng tiếng Việt',
    'Lên kế hoạch chi tiết cho 3 ngày ở Huế',
    'Viết hàm Dart sắp xếp danh sách đối tượng',
  ];
}
