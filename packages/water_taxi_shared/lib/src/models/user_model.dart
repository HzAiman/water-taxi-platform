/// Immutable data class representing a `users/{uid}` Firestore document.
class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UserModel.fromMap(
    Map<String, dynamic> data, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: (data['uid'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'phoneNumber': phoneNumber,
      };
}
