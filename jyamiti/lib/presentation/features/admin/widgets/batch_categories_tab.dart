import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/batch_category/batch_category_bloc.dart';
import '../bloc/batch_category/batch_category_event.dart';
import '../bloc/batch_category/batch_category_state.dart';

class BatchCategoriesTab extends StatefulWidget {
  const BatchCategoriesTab({super.key});

  @override
  State<BatchCategoriesTab> createState() => _BatchCategoriesTabState();
}

class _BatchCategoriesTabState extends State<BatchCategoriesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BatchCategoryBloc>().add(FetchBatchCategories());
    });
  }

  void _triggerRefresh() {
    context.read<BatchCategoryBloc>().add(FetchBatchCategories());
  }

  void _createCategory(String name, int maxMembers, int fees) {
    context.read<BatchCategoryBloc>().add(CreateBatchCategory(name: name, maxMembers: maxMembers, fees: fees));
  }

  void _editCategory(String id, String name, int maxMembers, int fees) {
    context.read<BatchCategoryBloc>().add(UpdateBatchCategory(id: id, name: name, maxMembers: maxMembers, fees: fees));
  }

  void _deleteCategory(String id) {
    context.read<BatchCategoryBloc>().add(DeleteBatchCategory(id));
  }

  void _showCategoryDialog({Map<String, dynamic>? category}) {
    final isEdit = category != null;
    final nameController = TextEditingController(text: isEdit ? category['name'] : '');
    final maxMembersController = TextEditingController(text: isEdit ? category['maxMembers'].toString() : '');
    final feesController = TextEditingController(text: isEdit ? category['fees'].toString() : '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text(isEdit ? 'Edit Category' : 'Create Category', style: TextStyle(color: context.textColor)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(labelText: 'Category Name', labelStyle: TextStyle(color: context.textColor70)),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: maxMembersController,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(labelText: 'Max Members', labelStyle: TextStyle(color: context.textColor70)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: feesController,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(labelText: 'Fees', labelStyle: TextStyle(color: context.textColor70)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: context.textColor60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final name = nameController.text.trim();
                  final members = int.parse(maxMembersController.text.trim());
                  final fees = int.parse(feesController.text.trim());
                  if (isEdit) {
                    _editCategory(category['id'], name, members, fees);
                  } else {
                    _createCategory(name, members, fees);
                  }
                  Navigator.pop(ctx);
                }
              },
              child: Text(isEdit ? 'Save' : 'Create', style: TextStyle(color: context.textColor)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text('Delete Category?', style: TextStyle(color: context.textColor)),
          content: Text('Are you sure you want to delete the category "$name"?', style: TextStyle(color: context.textColor70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: context.textColor60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteCategory(id);
              },
              child: Text('Delete', style: TextStyle(color: context.textColor)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BatchCategoryBloc, BatchCategoryState>(
      listener: (context, state) {
        if (state is BatchCategoryOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.green));
          _triggerRefresh();
        } else if (state is BatchCategoryOperationFailure) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.redAccent));
        }
      },
      builder: (context, state) {
        bool isLoading = state is BatchCategoryLoading || state is BatchCategoryInitial;
        List<dynamic> categories = [];
        if (state is BatchCategoryLoaded) {
          categories = state.categories;
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text('Batch Categories', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: context.textColor),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: context.isDark ? const [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: SafeArea(
              child: isLoading
              ? const Center(child: JyamitiLoader(color: Color(0xFF6366F1)))
              : categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_rounded, color: context.glassBorder, size: 80),
                          const SizedBox(height: 16),
                          Text('No Categories Yet', style: TextStyle(color: context.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('Create your first batch category.', style: TextStyle(color: context.textColor54)),
                        ],
                      ),
                    ).animate().fade()
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final c = categories[index];
                    return Container(
                      margin: EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: context.glassBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.05), blurRadius: 10)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 50, height: 50,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(child: Icon(Icons.class_outlined, color: Color(0xFF818CF8))),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c['name'], style: TextStyle(color: context.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('Max Members: ${c['maxMembers']}', style: TextStyle(color: context.textColor70, fontSize: 13)),
                                      const SizedBox(height: 2),
                                      Text('Fees: ${c['fees']}', style: TextStyle(color: context.textColor70, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit_rounded, color: context.textColor70),
                                  onPressed: () => _showCategoryDialog(category: c),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                  onPressed: () => _confirmDelete(c['id'], c['name']),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ).animate().fade(delay: (50 * index).ms).slideY(begin: 0.1, end: 0);
                  },
                ),
                ),
        ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ).animate().scale(delay: 200.ms),
        );
      },
    );
  }
}
