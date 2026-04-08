/// Immutable data class representing an `operators/{uid}` Firestore document.
class OperatorModel {
  const OperatorModel({
    required this.uid,
    required this.operatorId,
    required this.name,
    required this.email,
    required this.isOnline,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String operatorId;
  final String name;
  final String email;
  final bool isOnline;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory OperatorModel.fromMap(
    String uid,
    Map<String, dynamic> data, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OperatorModel(
      uid: uid,
      operatorId: (data['operatorId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      isOnline: data['isOnline'] == true,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  OperatorModel copyWith({
    String? uid,
    String? operatorId,
    String? name,
    String? email,
    bool? isOnline,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OperatorModel(
      uid: uid ?? this.uid,
      operatorId: operatorId ?? this.operatorId,
      name: name ?? this.name,
      email: email ?? this.email,
      isOnline: isOnline ?? this.isOnline,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'operatorId': operatorId,
        'name': name,
        'email': email,
      };
}
