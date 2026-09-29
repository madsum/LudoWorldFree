import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class OAuthButton extends StatelessWidget {
  final String providerName;
  final dynamic iconData;
  final Color backgroundColor;
  final Color textColor;
  final Color? iconColor;
  final VoidCallback onPressed;
  final bool isLoading;

  const OAuthButton({
    super.key,
    required this.providerName,
    required this.iconData,
    required this.backgroundColor,
    required this.textColor,
    this.iconColor,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 3,
          shadowColor: backgroundColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: backgroundColor == Colors.white
                ? BorderSide(color: Colors.grey.shade300, width: 1)
                : BorderSide.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconData is IconData)
                    Icon(
                      iconData as IconData,
                      size: 20,
                      color: iconColor ?? textColor,
                    )
                  else
                    FaIcon(
                      iconData,
                      size: 20,
                      color: iconColor ?? textColor,
                    ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with $providerName',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
