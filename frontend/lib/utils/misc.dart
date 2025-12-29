
// Chops up the list into batches
List<List<T>> chunkList<T>(List<T> list, int batchSize) {
  List<List<T>> chunks = [];
  for (var i = 0; i < list.length; i += batchSize) {
    int end = (i + batchSize < list.length) ? i + batchSize : list.length;
    chunks.add(list.sublist(i, end));
  }
  return chunks;
}

