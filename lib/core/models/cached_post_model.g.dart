// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_post_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CachedPostAdapter extends TypeAdapter<CachedPost> {
  @override
  final int typeId = 0;

  @override
  CachedPost read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CachedPost(
      id: fields[0] as String,
      userId: fields[1] as String,
      content: fields[2] as String?,
      images: (fields[3] as List).cast<String>(),
      location: fields[4] as String?,
      likesCount: fields[5] as int,
      commentsCount: fields[6] as int,
      sharesCount: fields[7] as int,
      createdAt: fields[8] as DateTime,
      updatedAt: fields[9] as DateTime,
      cachedAt: fields[10] as DateTime,
      isActive: fields[11] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, CachedPost obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.images)
      ..writeByte(4)
      ..write(obj.location)
      ..writeByte(5)
      ..write(obj.likesCount)
      ..writeByte(6)
      ..write(obj.commentsCount)
      ..writeByte(7)
      ..write(obj.sharesCount)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt)
      ..writeByte(10)
      ..write(obj.cachedAt)
      ..writeByte(11)
      ..write(obj.isActive);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedPostAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
