enum ChatSenderRole { employee, admin }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.employeeId,
    required this.senderRole,
    required this.text,
    required this.timestamp,
    this.senderName,
  });

  final String id;
  final String employeeId;
  final ChatSenderRole senderRole;
  final String text;
  final DateTime timestamp;
  final String? senderName;
}
