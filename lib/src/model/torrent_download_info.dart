class TorrentTaskDownloadInfo {
  /// Bytes uploaded
  int uploaded;

  /// Bytes downloaded
  int downloaded;

  /// Bytes left
  int left;

  TorrentTaskDownloadInfo({required this.uploaded, required this.downloaded, required this.left});
}
