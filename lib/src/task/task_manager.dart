import 'package:jtorrent/src/model/torrent.dart';
import 'package:jtorrent/src/task/torrent_task.dart';

class TaskManager {
  static final TaskManager _instance = TaskManager._internal();

  factory TaskManager() {
    return _instance;
  }

  TaskManager._internal();

  final List<TorrentTask> _tasks = [];

  void addTorrentTask(Torrent torrent) {}

  void removeTorrentTask(TorrentTask task) {
    _tasks.remove(task);
  }
}
