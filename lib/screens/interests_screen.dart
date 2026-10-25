import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../widgets/common_widgets.dart';

class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  // Añade tus imágenes reales en assets/images/ con estos nombres
  // Por ahora usa colores de fondo como placeholder
  final List<_Interest> _items = [
    _Interest('Nature', 'assets/images/nature.jpg', const Color(0xFF4A7C59)),
    _Interest('Urban', 'assets/images/urban.jpg', const Color(0xFF1A1A2E)),
    _Interest('Beach', 'assets/images/beach.jpg', const Color(0xFF0077B6)),
    _Interest('Hill', 'assets/images/hill.jpg', const Color(0xFF8B5E3C)),
    _Interest('Food', 'assets/images/food.jpg', const Color(0xFF2D2D2D)),
    _Interest('Wildlife', 'assets/images/wildlife.jpg', const Color(0xFF1B4332)),
    _Interest('People', 'assets/images/people.jpg', const Color(0xFF3A0CA3)),
    _Interest('Resort', 'assets/images/resort.jpg', const Color(0xFF6D4C41)),
    _Interest('Action', 'assets/images/action.jpg', const Color(0xFF0077B6)),
  ];

  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()),
                  GestureDetector(
                    onTap: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Skip',
                          style: TextStyle(
                              color: Color(0xFF6B4EFF),
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                      fontSize: 22,
                      color: Colors.black87,
                      fontWeight: FontWeight.w400),
                  children: [
                    TextSpan(text: 'Hi '),
                    TextSpan(
                      text: 'People',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ', What do you love\nmost about travelling?'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select 3 or more interests',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
              const SizedBox(height: 20),
              // Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final isSelected = _selected.contains(i);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selected.remove(i);
                          } else {
                            _selected.add(i);
                          }
                        });
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Image placeholder (replace with actual Image.asset)
                            Container(color: item.placeholderColor),
                            // Gradient overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.6),
                                  ],
                                ),
                              ),
                            ),
                            // Label + checkbox
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.transparent,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check,
                                            size: 14, color: Colors.black87)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Submit',
                color: const Color(0xFF6B4EFF),
                onPressed: () {
                  if (_selected.length < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Selecciona al menos 3 intereses')),
                    );
                    return;
                  }
                  // Navegar al homepage
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Interest {
  final String label;
  final String imagePath;
  final Color placeholderColor;

  _Interest(this.label, this.imagePath, this.placeholderColor);
}