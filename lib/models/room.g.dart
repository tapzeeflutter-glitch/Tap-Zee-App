part of 'room.dart';

class RoomAdapter extends TypeAdapter<Room> {
  @override
  final int typeId = 1;

  @override
  Room read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Room(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String,
      adminUid: fields[3] as String,
      location: fields[4] as GeoPoint,
      radius: fields[5] as double,
      approvedMembers: (fields[6] as List).cast<String>(),
      pendingMembers: (fields[7] as List).cast<String>(),
      rules: (fields[8] as List).cast<String>(),
      createdAt: fields[9] as Timestamp,
      blockedMembers: (fields[10] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Room obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.adminUid)
      ..writeByte(4)
      ..write(obj.location)
      ..writeByte(5)
      ..write(obj.radius)
      ..writeByte(6)
      ..write(obj.approvedMembers)
      ..writeByte(7)
      ..write(obj.pendingMembers)
      ..writeByte(8)
      ..write(obj.rules)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.blockedMembers);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
