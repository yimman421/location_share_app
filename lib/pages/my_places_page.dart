// lib/pages/my_places_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/personal_place_model.dart';
import '../providers/personal_places_provider.dart';

class MyPlacesPage extends StatefulWidget {
  final String userId;
  final Function(double lat, double lng, String name)? onNavigateToPlace;

  const MyPlacesPage({
    super.key,
    required this.userId,
    this.onNavigateToPlace,
  });

  @override
  State<MyPlacesPage> createState() => _MyPlacesPageState();
}

class _MyPlacesPageState extends State<MyPlacesPage> {
  String _selectedGroupFilter = '전체';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PersonalPlacesProvider>().fetchMyPlaces(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 장소'),
        actions: [
          // 그룹 필터
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: '그룹 필터',
            onSelected: (group) {
              setState(() => _selectedGroupFilter = group);
              context.read<PersonalPlacesProvider>().setGroupFilter(group);
            },
            itemBuilder: (context) {
              final provider = context.read<PersonalPlacesProvider>();
              final groups = {'전체', ...provider.allPlaces.expand((p) => p.groups)};
              
              return groups.map((group) {
                final count = provider.getPlaceCountByGroup(group);
                return PopupMenuItem(
                  value: group,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(group),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: group == _selectedGroupFilter
                              ? Colors.deepPurple
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 12,
                            color: group == _selectedGroupFilter
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: Consumer<PersonalPlacesProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final places = provider.filteredPlaces;

          if (places.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedGroupFilter == '전체'
                        ? '저장된 장소가 없습니다'
                        : '$_selectedGroupFilter 그룹에\n저장된 장소가 없습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.map),
                    label: const Text('지도에서 장소 추가하기'),
                  ),
                ],
              ),
            );
          }

          // 카테고리별로 그룹핑
          final byCategory = <String, List<PersonalPlaceModel>>{};
          for (final place in places) {
            byCategory.putIfAbsent(place.category, () => []).add(place);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: byCategory.length,
            itemBuilder: (context, index) {
              final category = byCategory.keys.elementAt(index);
              final categoryPlaces = byCategory[category]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 카테고리 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _getCategoryIcon(category),
                          size: 20,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${categoryPlaces.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepPurple[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 장소 카드들
                  ...categoryPlaces.map((place) => _buildPlaceCard(place)),
                  
                  const SizedBox(height: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlaceCard(PersonalPlaceModel place) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          _showPlaceDetailDialog(place);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      place.placeName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 액션 버튼들
                  IconButton(
                    icon: const Icon(Icons.navigation, size: 20),
                    tooltip: '길찾기',
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onNavigateToPlace?.call(
                        place.lat,
                        place.lng,
                        place.placeName,
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('삭제', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') {
                        _confirmDelete(place);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      place.address,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (place.groups.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: place.groups.map((group) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Text(
                        group,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[700],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (place.memo != null && place.memo!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.note, size: 14, color: Colors.amber[700]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          place.memo!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaceDetailDialog(PersonalPlaceModel place) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(place.placeName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(Icons.category, '카테고리', place.category),
            _buildInfoRow(Icons.location_on, '주소', place.address),
            _buildInfoRow(
              Icons.my_location,
              '좌표',
              '${place.lat.toStringAsFixed(6)}, ${place.lng.toStringAsFixed(6)}',
            ),
            if (place.memo != null && place.memo!.isNotEmpty)
              _buildInfoRow(Icons.note, '메모', place.memo!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              widget.onNavigateToPlace?.call(
                place.lat,
                place.lng,
                place.placeName,
              );
            },
            icon: const Icon(Icons.navigation),
            label: const Text('길찾기'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(PersonalPlaceModel place) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('장소 삭제'),
        content: Text('${place.placeName}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final provider = context.read<PersonalPlacesProvider>();
              final success = await provider.deletePlace(
                place.id,
                widget.userId,
              );
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? '✅ 삭제되었습니다' : '❌ 삭제 실패',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case PlaceCategory.home:
        return Icons.home;
      case PlaceCategory.work:
        return Icons.work;
      case PlaceCategory.frequent:
        return Icons.star;
      case PlaceCategory.restaurant:
        return Icons.restaurant;
      default:
        return Icons.place;
    }
  }
}