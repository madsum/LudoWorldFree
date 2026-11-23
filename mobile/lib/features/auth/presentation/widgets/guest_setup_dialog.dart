import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/top_notice.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../controllers/auth_controller.dart';

class CountryItem {
  final String name;
  final String flag;

  const CountryItem(this.name, this.flag);
}

class AvatarItem {
  final String id;
  final String title;
  final String imagePath;

  const AvatarItem({
    required this.id,
    required this.title,
    required this.imagePath,
  });
}

class GuestSetupDialog extends ConsumerStatefulWidget {
  final bool isEditMode;
  final String? initialName;
  final String? initialAvatarUrl;
  final String? initialCountry;
  final String? initialCountryFlag;

  const GuestSetupDialog({
    super.key,
    this.isEditMode = false,
    this.initialName,
    this.initialAvatarUrl,
    this.initialCountry,
    this.initialCountryFlag,
  });

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GuestSetupDialog(),
    );
  }

  static void showEditProfile(
    BuildContext context, {
    required String currentName,
    required String? currentAvatarUrl,
    required String currentCountry,
    required String currentCountryFlag,
  }) {
    showDialog(
      context: context,
      builder: (context) => GuestSetupDialog(
        isEditMode: true,
        initialName: currentName,
        initialAvatarUrl: currentAvatarUrl,
        initialCountry: currentCountry,
        initialCountryFlag: currentCountryFlag,
      ),
    );
  }

  @override
  ConsumerState<GuestSetupDialog> createState() => _GuestSetupDialogState();
}

class _GuestSetupDialogState extends ConsumerState<GuestSetupDialog> {
  late TextEditingController _nameController;
  late CountryItem _selectedCountry;
  late String _selectedAvatarId;
  Uint8List? _customAvatarBytes;
  String? _customAvatarName;
  String? _existingCustomAvatarUrl;
  String? _avatarError;
  bool _isPickingAvatar = false;

  static const int _maxAvatarBytes = 5 * 1024 * 1024;
  static const int _maxAvatarDimension = 4096;
  static const int _maxAvatarPixels = 16 * 1024 * 1024;

  static const List<CountryItem> _allCountries = [
    CountryItem('World', 'assets/images/world.png'),
    CountryItem('Afghanistan', '🇦🇫'),
    CountryItem('Albania', '🇦🇱'),
    CountryItem('Algeria', '🇩🇿'),
    CountryItem('Andorra', '🇦🇩'),
    CountryItem('Angola', '🇦🇴'),
    CountryItem('Antigua and Barbuda', '🇦🇬'),
    CountryItem('Argentina', '🇦🇷'),
    CountryItem('Armenia', '🇦🇲'),
    CountryItem('Australia', '🇦🇺'),
    CountryItem('Austria', '🇦🇹'),
    CountryItem('Azerbaijan', '🇦🇿'),
    CountryItem('Bahamas', '🇧🇸'),
    CountryItem('Bahrain', '🇧🇭'),
    CountryItem('Bangladesh', '🇧🇩'),
    CountryItem('Barbados', '🇧🇧'),
    CountryItem('Belarus', '🇧🇾'),
    CountryItem('Belgium', '🇧🇪'),
    CountryItem('Belize', '🇧🇿'),
    CountryItem('Benin', '🇧🇯'),
    CountryItem('Bhutan', '🇧🇹'),
    CountryItem('Bolivia', '🇧🇴'),
    CountryItem('Bosnia and Herzegovina', '🇧🇦'),
    CountryItem('Botswana', '🇧🇼'),
    CountryItem('Brazil', '🇧🇷'),
    CountryItem('Brunei', '🇧🇳'),
    CountryItem('Bulgaria', '🇧🇬'),
    CountryItem('Burkina Faso', '🇧🇫'),
    CountryItem('Burundi', '🇧🇮'),
    CountryItem('Cambodia', '🇰🇭'),
    CountryItem('Cameroon', '🇨🇲'),
    CountryItem('Canada', '🇨🇦'),
    CountryItem('Cape Verde', '🇨🇻'),
    CountryItem('Central African Republic', '🇨🇫'),
    CountryItem('Chad', '🇹🇩'),
    CountryItem('Chile', '🇨🇱'),
    CountryItem('China', '🇨🇳'),
    CountryItem('Colombia', '🇨🇴'),
    CountryItem('Comoros', '🇰🇲'),
    CountryItem('Congo', '🇨🇬'),
    CountryItem('Costa Rica', '🇨🇷'),
    CountryItem('Croatia', '🇭🇷'),
    CountryItem('Cuba', '🇨🇺'),
    CountryItem('Cyprus', '🇨🇾'),
    CountryItem('Czech Republic', '🇨🇿'),
    CountryItem('Denmark', '🇩🇰'),
    CountryItem('Djibouti', '🇩🇯'),
    CountryItem('Dominica', '🇩🇲'),
    CountryItem('Dominican Republic', '🇩🇴'),
    CountryItem('Ecuador', '🇪🇨'),
    CountryItem('Egypt', '🇪🇬'),
    CountryItem('El Salvador', '🇸🇻'),
    CountryItem('Equatorial Guinea', '🇬🇶'),
    CountryItem('Eritrea', '🇪🇷'),
    CountryItem('Estonia', '🇪🇪'),
    CountryItem('Eswatini', '🇸ℤ'),
    CountryItem('Ethiopia', '🇪🇹'),
    CountryItem('Fiji', '🇫🇯'),
    CountryItem('Finland', '🇫🇮'),
    CountryItem('France', '🇫🇷'),
    CountryItem('Gabon', '🇬🇦'),
    CountryItem('Gambia', '🇬🇲'),
    CountryItem('Georgia', '🇬🇪'),
    CountryItem('Germany', '🇩🇪'),
    CountryItem('Ghana', '🇬🇭'),
    CountryItem('Greece', '🇬🇷'),
    CountryItem('Grenada', '🇬🇩'),
    CountryItem('Guatemala', '🇬🇹'),
    CountryItem('Guinea', '🇬🇳'),
    CountryItem('Guinea-Bissau', '🇬🇼'),
    CountryItem('Guyana', '🇬🇾'),
    CountryItem('Haiti', '🇭🇹'),
    CountryItem('Honduras', '🇭HN'),
    CountryItem('Hungary', '🇭🇺'),
    CountryItem('Iceland', '🇮🇸'),
    CountryItem('India', '🇮🇳'),
    CountryItem('Indonesia', '🇮🇩'),
    CountryItem('Iran', '🇮🇷'),
    CountryItem('Iraq', '🇮🇶'),
    CountryItem('Ireland', '🇮🇪'),
    CountryItem('Israel', '🇮🇱'),
    CountryItem('Italy', '🇮🇹'),
    CountryItem('Jamaica', '🇯🇲'),
    CountryItem('Japan', '🇯🇵'),
    CountryItem('Jordan', '🇯🇴'),
    CountryItem('Kazakhstan', '🇰🇿'),
    CountryItem('Kenya', '🇰🇪'),
    CountryItem('Kiribati', '🇰🇮'),
    CountryItem('Kuwait', '🇰🇼'),
    CountryItem('Kyrgyzstan', '🇰🇬'),
    CountryItem('Laos', '🇱🇦'),
    CountryItem('Latvia', '🇱🇻'),
    CountryItem('Lebanon', '🇱🇧'),
    CountryItem('Lesotho', '🇱🇸'),
    CountryItem('Liberia', '🇱🇷'),
    CountryItem('Libya', '🇱🇾'),
    CountryItem('Liechtenstein', '🇱🇮'),
    CountryItem('Lithuania', '🇱🇹'),
    CountryItem('Luxembourg', '🇱🇺'),
    CountryItem('Madagascar', '🇲🇬'),
    CountryItem('Malawi', '🇲🇼'),
    CountryItem('Malaysia', '🇲🇾'),
    CountryItem('Maldives', '🇲🇻'),
    CountryItem('Mali', '🇲🇱'),
    CountryItem('Malta', '🇲🇹'),
    CountryItem('Marshall Islands', '🇲🇭'),
    CountryItem('Mauritania', '🇲🇷'),
    CountryItem('Mauritius', '🇲🇺'),
    CountryItem('Mexico', '🇲🇽'),
    CountryItem('Micronesia', '🇫🇲'),
    CountryItem('Moldova', '🇲🇩'),
    CountryItem('Monaco', '🇲🇨'),
    CountryItem('Mongolia', '🇲🇳'),
    CountryItem('Montenegro', '🇲🇪'),
    CountryItem('Morocco', '🇲🇦'),
    CountryItem('Mozambique', '🇲🇿'),
    CountryItem('Myanmar', '🇲🇲'),
    CountryItem('Namibia', '🇳🇦'),
    CountryItem('Nauru', '🇳🇷'),
    CountryItem('Nepal', '🇳🇵'),
    CountryItem('Netherlands', '🇳🇱'),
    CountryItem('New Zealand', '🇳🇿'),
    CountryItem('Nicaragua', '🇳🇮'),
    CountryItem('Niger', '🇳🇪'),
    CountryItem('Nigeria', '🇳🇬'),
    CountryItem('North Korea', '🇰🇵'),
    CountryItem('North Macedonia', '🇲🇰'),
    CountryItem('Norway', '🇳🇴'),
    CountryItem('Oman', '🇴🇲'),
    CountryItem('Pakistan', '🇵🇰'),
    CountryItem('Palau', '🇵🇼'),
    CountryItem('Palestine', '🇵🇸'),
    CountryItem('Panama', '🇵🇦'),
    CountryItem('Papua New Guinea', '🇵🇬'),
    CountryItem('Paraguay', '🇵🇾'),
    CountryItem('Peru', '🇵🇪'),
    CountryItem('Philippines', '🇵🇭'),
    CountryItem('Poland', '🇵🇱'),
    CountryItem('Portugal', '🇵🇹'),
    CountryItem('Qatar', '🇶🇦'),
    CountryItem('Romania', '🇷🇴'),
    CountryItem('Russia', '🇷🇺'),
    CountryItem('Rwanda', '🇷🇼'),
    CountryItem('Saint Kitts and Nevis', '🇰🇳'),
    CountryItem('Saint Lucia', '🇱🇨'),
    CountryItem('Saint Vincent and the Grenadines', '🇻🇨'),
    CountryItem('Samoa', '🇼🇸'),
    CountryItem('San Marino', '🇸🇲'),
    CountryItem('Sao Tome and Principe', '🇸🇹'),
    CountryItem('Saudi Arabia', '🇸🇦'),
    CountryItem('Senegal', '🇸🇳'),
    CountryItem('Serbia', '🇷🇸'),
    CountryItem('Seychelles', '🇸🇨'),
    CountryItem('Sierra Leone', '🇸🇱'),
    CountryItem('Singapore', '🇸🇬'),
    CountryItem('Slovakia', '🇸🇰'),
    CountryItem('Slovenia', '🇸🇮'),
    CountryItem('Solomon Islands', '🇸🇧'),
    CountryItem('Somalia', '🇸🇴'),
    CountryItem('South Africa', '🇿🇦'),
    CountryItem('South Korea', '🇰🇷'),
    CountryItem('South Sudan', '🇸🇸'),
    CountryItem('Spain', '🇪🇸'),
    CountryItem('Sri Lanka', '🇱🇰'),
    CountryItem('Sudan', '🇸🇩'),
    CountryItem('Suriname', '🇸🇷'),
    CountryItem('Sweden', '🇸🇪'),
    CountryItem('Switzerland', '🇨🇭'),
    CountryItem('Syria', '🇸🇾'),
    CountryItem('Taiwan', '🇹🇼'),
    CountryItem('Tajikistan', '🇹🇯'),
    CountryItem('Tanzania', '🇹🇿'),
    CountryItem('Thailand', '🇹🇭'),
    CountryItem('Timor-Leste', '🇹🇱'),
    CountryItem('Togo', '🇹🇬'),
    CountryItem('Tonga', '🇹🇴'),
    CountryItem('Trinidad and Tobago', '🇹🇹'),
    CountryItem('Tunisia', '🇹🇳'),
    CountryItem('Turkey', '🇹🇷'),
    CountryItem('Turkmenistan', '🇹🇲'),
    CountryItem('Tuvalu', '🇹🇻'),
    CountryItem('Uganda', '🇺🇬'),
    CountryItem('Ukraine', '🇺🇦'),
    CountryItem('United Arab Emirates', '🇦🇪'),
    CountryItem('United Kingdom', '🇬🇧'),
    CountryItem('United States', '🇺🇸'),
    CountryItem('Uruguay', '🇺🇾'),
    CountryItem('Uzbekistan', '🇺🇿'),
    CountryItem('Vanuatu', '🇻🇺'),
    CountryItem('Vatican City', '🇻🇦'),
    CountryItem('Venezuela', '🇻🇪'),
    CountryItem('Vietnam', '🇻🇳'),
    CountryItem('Yemen', '🇾🇪'),
    CountryItem('Zambia', '🇿🇲'),
    CountryItem('Zimbabwe', '🇿🇼'),
  ];

  static const List<AvatarItem> _avatars = [
    AvatarItem(
        id: 'mask_black_1',
        title: 'Black Mask 1',
        imagePath: 'assets/images/black-mask.webp'),
    AvatarItem(
        id: 'mask_black_2',
        title: 'Black Mask 2',
        imagePath: 'assets/images/black-mask2.webp'),
    AvatarItem(
        id: 'mask_black_4',
        title: 'Black Mask 4',
        imagePath: 'assets/images/black-mask4.webp'),
    AvatarItem(
        id: 'mask_blue_1',
        title: 'Blue Mask 1',
        imagePath: 'assets/images/blue-mask.webp'),
    AvatarItem(
        id: 'mask_blue_2',
        title: 'Blue Mask 2',
        imagePath: 'assets/images/blue-mask (1).webp'),
    AvatarItem(
        id: 'mask_blue_7',
        title: 'Blue Mask 7',
        imagePath: 'assets/images/blue-mask7.webp'),
    AvatarItem(
        id: 'mask_blue_8',
        title: 'Blue Mask 8',
        imagePath: 'assets/images/blue-mask8.webp'),
    AvatarItem(
        id: 'mask_green',
        title: 'Green Mask',
        imagePath: 'assets/images/green-mask.webp'),
    AvatarItem(
        id: 'mask_pest',
        title: 'Pest Mask',
        imagePath: 'assets/images/pest-mask.webp'),
    AvatarItem(
        id: 'mask_red',
        title: 'Red Mask',
        imagePath: 'assets/images/red-mask.webp'),
  ];

  @override
  void initState() {
    super.initState();
    final randomNum = (1000 + (DateTime.now().millisecondsSinceEpoch % 8999));
    final defaultName = widget.initialName ?? 'Guest_$randomNum';
    _nameController = TextEditingController(text: defaultName);

    _selectedCountry = _allCountries.firstWhere(
      (c) => c.name == (widget.initialCountry ?? 'World'),
      orElse: () => _allCountries.first,
    );

    final initialAvatar = widget.initialAvatarUrl;
    final isDefaultAvatar =
        _avatars.any((avatar) => avatar.imagePath == initialAvatar);
    _selectedAvatarId = isDefaultAvatar || initialAvatar == null
        ? initialAvatar ?? _avatars.first.imagePath
        : _avatars.first.imagePath;
    if (!isDefaultAvatar &&
        initialAvatar != null &&
        initialAvatar.startsWith('http')) {
      _existingCustomAvatarUrl = initialAvatar;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildFlagWidget(String flag, {double size = 22}) {
    if (flag == '🌐' ||
        flag == 'assets/images/world.png' ||
        flag.contains('world')) {
      return Image.asset(
        'assets/images/world.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text('🌐', style: TextStyle(fontSize: size)),
      );
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }

  void _openCountrySearchPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CountrySearchSheet(
        allCountries: _allCountries,
        selectedCountry: _selectedCountry,
        onSelected: (country) {
          setState(() => _selectedCountry = country);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _pickAvatarImage() async {
    if (_isPickingAvatar || ref.read(authControllerProvider).isLoading) return;
    setState(() {
      _isPickingAvatar = true;
      _avatarError = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        allowMultiple: false,
      );
      final file =
          result == null || result.files.isEmpty ? null : result.files.first;
      if (file == null) return;

      final extension = file.extension?.toLowerCase();
      if (!const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
        _setAvatarError('Choose a PNG, JPG, JPEG, or WebP image.');
        return;
      }

      // file.bytes is populated directly by file_picker (no withReadStream).
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      if (bytes.isEmpty) {
        _setAvatarError('The selected file could not be read.');
        return;
      }
      if (bytes.length > _maxAvatarBytes) {
        _setAvatarError('Image must be 5 MB or smaller.');
        return;
      }

      // Decode the actual bytes rather than parsing format-specific headers.
      // Header parsing can reject valid JPEG/WebP files produced by device
      // photo providers even though Flutter can render them.
      final codec = await ui.instantiateImageCodec(bytes);
      late final int width;
      late final int height;
      try {
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (width < 32 ||
          height < 32 ||
          width > _maxAvatarDimension ||
          height > _maxAvatarDimension ||
          width * height > _maxAvatarPixels) {
        _setAvatarError(
            'Image dimensions must be at least 32×32 and no larger than 4096×4096.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _customAvatarBytes = bytes;
        _customAvatarName = file.name;
        _existingCustomAvatarUrl = null;
        _avatarError = null;
      });
    } on Object {
      _setAvatarError(
          'This image could not be opened. Choose a valid PNG, JPG, JPEG, or WebP file.');
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _setAvatarError(String message) {
    if (!mounted) return;
    setState(() => _avatarError = message);
  }

  void _selectDefaultAvatar(AvatarItem avatar) {
    setState(() {
      _selectedAvatarId = avatar.imagePath;
      _customAvatarBytes = null;
      _customAvatarName = null;
      _existingCustomAvatarUrl = null;
      _avatarError = null;
    });
  }

  void _clearCustomAvatar() {
    setState(() {
      _customAvatarBytes = null;
      _customAvatarName = null;
      _existingCustomAvatarUrl = null;
      _avatarError = null;
    });
  }

  Widget _buildAvatarPreview() {
    final bytes = _customAvatarBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded),
      );
    }
    final url = _existingCustomAvatarUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          _selectedAvatarId,
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      _selectedAvatarId,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded),
    );
  }

  void _handleSaveAndPlay() async {
    if (ref.read(authControllerProvider).isLoading || _isPickingAvatar) return;
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    final name = _nameController.text.trim().isEmpty
        ? 'Guest Player'
        : _nameController.text.trim();
    final customAvatarBytes = _customAvatarBytes;
    final defaultAvatarUrl = _selectedAvatarId;
    final profileAvatarUrl = customAvatarBytes == null
        ? _existingCustomAvatarUrl ?? defaultAvatarUrl
        : defaultAvatarUrl;

    bool success;
    if (widget.isEditMode) {
      success =
          await ref.read(authControllerProvider.notifier).updateUserProfile(
                name: name,
                avatarUrl: profileAvatarUrl,
                country: _selectedCountry.name,
                countryFlag: _selectedCountry.flag,
              );
    } else {
      success = await ref.read(authControllerProvider.notifier).signInAsGuest(
            name: name,
            avatarUrl: profileAvatarUrl,
            country: _selectedCountry.name,
            countryFlag: _selectedCountry.flag,
          );
    }

    var uploadFailed = false;
    if (success && customAvatarBytes != null) {
      uploadFailed =
          !await ref.read(authControllerProvider.notifier).uploadProfileAvatar(
                bytes: customAvatarBytes,
                fileName: _customAvatarName ?? 'profile-image.png',
              );
    }

    if (success && mounted) {
      Navigator.of(context).pop();
      if (!widget.isEditMode) {
        context.go('/home');
      }
      if (uploadFailed) {
        TopNotice.showOnOverlay(
          rootOverlay,
          'Image upload failed. Your selected default avatar was saved.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return AlertDialog(
      backgroundColor: AppColors.bgNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.gold, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Title
              Text(
                widget.isEditMode
                    ? 'EDIT PLAYER PROFILE'
                    : 'GUEST PROFILE SETUP',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isEditMode
                    ? 'Update your name, country & profile image below!'
                    : 'Choose a default avatar or upload your own image!',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Player Name Field
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'YOUR PLAYER NAME',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white60),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black38,
                  prefixIcon:
                      const Icon(Icons.person_rounded, color: AppColors.gold),
                  hintText: 'Enter name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.glassBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.gold, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Select Avatar Grid
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CHOOSE MASK AVATAR',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white60),
                    ),
                    Text(
                      '${_avatars.length} Masks',
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: AppColors.gold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 125,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _avatars.length,
                  itemBuilder: (context, index) {
                    final avatar = _avatars[index];
                    final isSelected = _customAvatarBytes == null &&
                        _existingCustomAvatarUrl == null &&
                        avatar.imagePath == _selectedAvatarId;
                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: 'Select ${avatar.title} avatar',
                      child: Tooltip(
                        message: avatar.title,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _selectDefaultAvatar(avatar),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.gold
                                    : Colors.white24,
                                width: isSelected ? 3 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.5),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                avatar.imagePath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Semantics(
                    label: 'Selected profile image preview',
                    image: true,
                    child: Container(
                      width: 54,
                      height: 54,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold, width: 2),
                      ),
                      child: _buildAvatarPreview(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Browse and upload a profile image',
                      child: OutlinedButton.icon(
                        onPressed: _isPickingAvatar || authState.isLoading
                            ? null
                            : _pickAvatarImage,
                        icon: _isPickingAvatar
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                          _customAvatarName ?? 'Browse / Upload Image',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold),
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                    ),
                  ),
                  if (_customAvatarBytes != null ||
                      _existingCustomAvatarUrl != null)
                    IconButton(
                      tooltip:
                          'Clear custom image and use selected default avatar',
                      onPressed: _clearCustomAvatar,
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PNG, JPG, JPEG, or WebP • max 5 MB',
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ),
              if (_avatarError != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _avatarError!,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFF8A80),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Searchable Country Selector Button
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SELECT YOUR COUNTRY (TYPE TO SEARCH)',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white60),
                ),
              ),
              const SizedBox(height: 6),

              GestureDetector(
                onTap: _openCountrySearchPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.6),
                        width: 1.2),
                  ),
                  child: Row(
                    children: [
                      _buildFlagWidget(_selectedCountry.flag, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedCountry.name,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.search_rounded,
                          color: AppColors.gold, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: CustomGameButton(
                      text: widget.isEditMode ? 'SAVE' : 'SAVE & PLAY',
                      icon: widget.isEditMode
                          ? Icons.save_rounded
                          : Icons.play_arrow_rounded,
                      isLoading: authState.isLoading,
                      onPressed: _handleSaveAndPlay,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable Bottom Sheet Picker for Countries
class _CountrySearchSheet extends StatefulWidget {
  final List<CountryItem> allCountries;
  final CountryItem selectedCountry;
  final ValueChanged<CountryItem> onSelected;

  const _CountrySearchSheet({
    required this.allCountries,
    required this.selectedCountry,
    required this.onSelected,
  });

  @override
  State<_CountrySearchSheet> createState() => _CountrySearchSheetState();
}

class _CountrySearchSheetState extends State<_CountrySearchSheet> {
  late List<CountryItem> _filteredList;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _filteredList = widget.allCountries;
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildFlagWidget(String flag, {double size = 22}) {
    if (flag == '🌐' ||
        flag == 'assets/images/world.png' ||
        flag.contains('world')) {
      return Image.asset(
        'assets/images/world.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text('🌐', style: TextStyle(fontSize: size)),
      );
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredList = widget.allCountries;
      } else {
        _filteredList = widget.allCountries
            .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.75 + keyboardSpace,
      decoration: const BoxDecoration(
        color: AppColors.bgNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.gold, width: 2)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + keyboardSpace),
      child: Column(
        children: [
          // Drag handle indicator
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'SEARCH YOUR COUNTRY',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),

          // Real-time Search Input Field
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onSearchChanged,
            style: GoogleFonts.poppins(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type country name (e.g. World, Zim, Ned)...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.gold),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.black38,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Filtered Country List
          Expanded(
            child: _filteredList.isEmpty
                ? Center(
                    child: Text(
                      'No countries match "${_searchController.text}"',
                      style: GoogleFonts.poppins(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filteredList.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final country = _filteredList[index];
                      final isSelected =
                          country.name == widget.selectedCountry.name;

                      return Material(
                        color: AppColors.bgNavy,
                        child: ListTile(
                          onTap: () => widget.onSelected(country),
                          leading: _buildFlagWidget(country.flag, size: 24),
                          title: Text(
                            country.name,
                            style: GoogleFonts.poppins(
                              color:
                                  isSelected ? AppColors.gold : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded,
                                  color: AppColors.gold, size: 20)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
