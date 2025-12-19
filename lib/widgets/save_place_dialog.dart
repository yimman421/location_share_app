// lib/widgets/save_place_dialog.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/personal_place_model.dart';
import '../providers/personal_places_provider.dart';
import '../providers/locations_provider.dart';

class SavePlaceDialog extends StatefulWidget {
  final String userId;
  final String address;
  final double lat;
  final double lng;
  final List<Map<String, String>> availableGroups;
  final VoidCallback? onPlaceSaved; // ✅ 저장 후 콜백 추가

  const SavePlaceDialog({
    super.key,
    required this.userId,
    required this.address,
    required this.lat,
    required this.lng,
    required this.availableGroups,
    this.onPlaceSaved, // ✅ 콜백 옵션
  });

  @override
  State<SavePlaceDialog> createState() => _SavePlaceDialogState();
}

class _SavePlaceDialogState extends State<SavePlaceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _placeNameController = TextEditingController();
  final _memoController = TextEditingController();
  final _customCategoryController = TextEditingController();

  String _selectedCategory = PlaceCategory.other;
  bool _useCustomCategory = false;
  final Set<String> _selectedGroups = {'전체'};

  @override
  void initState() {
    super.initState();
    // 주소를 기본 이름으로 설정
    _placeNameController.text = _extractPlaceName(widget.address);
  }

  @override
  void dispose() {
    _placeNameController.dispose();
    _memoController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  String _extractPlaceName(String address) {
    // 주소에서 의미있는 부분 추출 (예: "서울 강남구 테헤란로 123" -> "테헤란로 123")
    final parts = address.split(' ');
    if (parts.length > 2) {
      return parts.sublist(parts.length - 2).join(' ');
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 헤더
                Row(
                  children: [
                    const Icon(Icons.place, color: Colors.deepPurple, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      '장소 저장',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 32),

                // ✅ 장소 이름
                TextFormField(
                  controller: _placeNameController,
                  decoration: const InputDecoration(
                    labelText: '장소 이름 *',
                    hintText: '예: 우리집, 회사',
                    prefixIcon: Icon(Icons.label),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '장소 이름을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ✅ 카테고리 선택
                const Text(
                  '카테고리 *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                
                // 미리 정의된 카테고리
                if (!_useCustomCategory)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PlaceCategory.predefined.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedCategory = cat);
                          }
                        },
                        selectedColor: Colors.deepPurple,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                
                // 직접 입력 옵션
                Row(
                  children: [
                    Checkbox(
                      value: _useCustomCategory,
                      onChanged: (value) {
                        setState(() => _useCustomCategory = value ?? false);
                      },
                    ),
                    const Text('직접 입력'),
                  ],
                ),
                
                if (_useCustomCategory)
                  TextFormField(
                    controller: _customCategoryController,
                    decoration: const InputDecoration(
                      hintText: '카테고리 입력',
                      prefixIcon: Icon(Icons.edit),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_useCustomCategory && (value == null || value.trim().isEmpty)) {
                        return '카테고리를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                
                const SizedBox(height: 16),

                // ✅ 주소 (읽기 전용)
                TextFormField(
                  initialValue: widget.address,
                  decoration: const InputDecoration(
                    labelText: '주소',
                    prefixIcon: Icon(Icons.location_on),
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // ✅ 그룹 선택
                const Text(
                  '그룹 선택 *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableGroups.map((group) {
                      final groupName = group['name']!;
                      final isSelected = _selectedGroups.contains(groupName);
                      
                      return FilterChip(
                        label: Text(groupName),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (groupName == '전체') {
                                // ✅ '전체' 클릭 시 다른 모든 그룹 해제
                                _selectedGroups.clear();
                                _selectedGroups.add('전체');
                              } else {
                                // ✅ 개별 그룹 클릭 시 '전체' 해제
                                _selectedGroups.remove('전체');
                                _selectedGroups.add(groupName);
                              }
                            } else {
                              // ✅ 선택 해제
                              _selectedGroups.remove(groupName);
                              // ✅ 아무것도 선택 안 되면 '전체' 자동 선택
                              if (_selectedGroups.isEmpty) {
                                _selectedGroups.add('전체');
                              }
                            }
                          });
                        },
                        selectedColor: Colors.blue[100],
                        checkmarkColor: Colors.blue[700],
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // ✅ 메모 (선택)
                TextFormField(
                  controller: _memoController,
                  decoration: const InputDecoration(
                    labelText: '메모 (선택)',
                    hintText: '추가 정보를 입력하세요',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),

                // ✅ 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _savePlace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.save),
                        label: const Text(
                          '저장',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _savePlace() async {
    debugPrint('');
    debugPrint('💾 ════════════════════ 장소 저장 시작 ════════════════════');
    
    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ 폼 유효성 검사 실패');
      return;
    }

    if (_selectedGroups.isEmpty) {
      debugPrint('❌ 그룹 선택 안됨');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 하나의 그룹을 선택해주세요')),
      );
      return;
    }

    final provider = context.read<PersonalPlacesProvider>();
    
    final category = _useCustomCategory
        ? _customCategoryController.text.trim()
        : _selectedCategory;

    debugPrint('📝 장소 정보:');
    debugPrint('   이름: ${_placeNameController.text.trim()}');
    debugPrint('   카테고리: $category');
    debugPrint('   주소: ${widget.address}');
    debugPrint('   좌표: (${widget.lat}, ${widget.lng})');
    debugPrint('   그룹: ${_selectedGroups.toList()}');

    final success = await provider.savePlace(
      userId: widget.userId,
      placeName: _placeNameController.text.trim(),
      category: category,
      address: widget.address,
      lat: widget.lat,
      lng: widget.lng,
      groups: _selectedGroups.toList(),
      memo: _memoController.text.trim().isEmpty 
          ? null 
          : _memoController.text.trim(),
    );

    if (!mounted) {
      debugPrint('⚠️ Widget disposed during save');
      return;
    }

    if (success) {
      debugPrint('✅ 장소 저장 성공');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 장소가 저장되었습니다'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
      // ✅ 콜백 호출 (있으면)
      widget.onPlaceSaved?.call();
      
      debugPrint('💾 ════════════════════ 장소 저장 완료 ════════════════════');
      debugPrint('');
      
      Navigator.pop(context, true);
    } else {
      debugPrint('❌ 장소 저장 실패');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ 저장 중 오류가 발생했습니다'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      
      debugPrint('💾 ════════════════════ 장소 저장 실패 ════════════════════');
      debugPrint('');
    }
  }
}