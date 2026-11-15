extends RefCounted
## Reads and writes one saved world in a folder:
##   meta.json    seed, clock, player, inventory, furnaces
##   chunks.bin   only the chunks the player changed, compressed
## Files are written under a temporary name and renamed, so a crash in the
## middle of saving cannot damage the previous save.

const DIR := "user://world"
const VERSION := 1
const CHUNK_BYTES := 16 * 16 * 128


static func exists(dir := DIR) -> bool:
	return FileAccess.file_exists(dir + "/meta.json") and FileAccess.file_exists(dir + "/chunks.bin")


static func erase(dir := DIR) -> void:
	for file: String in ["meta.json", "chunks.bin", "meta.json.tmp", "chunks.bin.tmp"]:
		if FileAccess.file_exists(dir + "/" + file):
			DirAccess.remove_absolute(dir + "/" + file)


## modified: Vector2i -> [PackedByteArray data, int max_y].
static func write(dir: String, meta: Dictionary, modified: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var f := FileAccess.open(dir + "/chunks.bin.tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(VERSION)
	f.store_32(modified.size())
	for pos: Vector2i in modified:
		var entry: Array = modified[pos]
		var packed: PackedByteArray = (entry[0] as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD)
		f.store_32(pos.x & 0xffffffff)
		f.store_32(pos.y & 0xffffffff)
		f.store_16(entry[1])
		f.store_32(packed.size())
		f.store_buffer(packed)
	f.close()

	meta["version"] = VERSION
	var m := FileAccess.open(dir + "/meta.json.tmp", FileAccess.WRITE)
	if m == null:
		return false
	m.store_string(JSON.stringify(meta))
	m.close()

	var d := DirAccess.open(dir)
	if d == null:
		return false
	return d.rename("chunks.bin.tmp", "chunks.bin") == OK and d.rename("meta.json.tmp", "meta.json") == OK


## Returns { "meta": Dictionary, "modified": Dictionary }, or {} when there is
## no usable save.
static func read(dir := DIR) -> Dictionary:
	if not exists(dir):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(dir + "/meta.json")) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION:
		return {}
	var f := FileAccess.open(dir + "/chunks.bin", FileAccess.READ)
	if f == null or f.get_32() != VERSION:
		return {}
	var modified := {}
	var count := f.get_32()
	for i in count:
		var x := _signed(f.get_32())
		var z := _signed(f.get_32())
		var max_y := f.get_16()
		var size := f.get_32()
		var data := f.get_buffer(size).decompress(CHUNK_BYTES, FileAccess.COMPRESSION_ZSTD)
		if data.size() != CHUNK_BYTES:
			return {}
		modified[Vector2i(x, z)] = [data, max_y]
	return {"meta": parsed, "modified": modified}


static func _signed(v: int) -> int:
	return v - 0x100000000 if v >= 0x80000000 else v
