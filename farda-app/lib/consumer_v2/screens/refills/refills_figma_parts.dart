import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Shared presentation for the preview and signed-in refill station.
/// The values and callbacks are supplied by their respective owners.
class RefillsPageHeader extends StatelessWidget {
  const RefillsPageHeader({super.key, this.onOpenProfile});

  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        'farda.',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 30,
          height: 39 / 30,
          fontWeight: FontWeight.w600,
          color: FardaConsumerColors.brand,
        ),
      ),
      Semantics(
        button: onOpenProfile != null,
        label: 'Open your space',
        child: Material(
          color: FardaConsumerColors.soft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(child: Text('YO', style: FardaConsumerType.label)),
            ),
          ),
        ),
      ),
    ],
  );
}

class RefillsIntro extends StatelessWidget {
  const RefillsIntro({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'A LITTLE HEAD START',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 10,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: FardaConsumerColors.textSecondary,
        ),
      ),
      SizedBox(height: 8),
      Text(
        'Refill, with less rush.',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 32,
          height: 36 / 32,
          fontWeight: FontWeight.w600,
          color: FardaConsumerColors.brand,
        ),
      ),
      SizedBox(height: 8),
      Text(
        'Your supply and next step.',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 14,
          height: 20 / 14,
          color: FardaConsumerColors.textSecondary,
        ),
      ),
    ],
  );
}

class RefillsSupplyHero extends StatelessWidget {
  const RefillsSupplyHero({
    super.key,
    required this.headline,
    required this.value,
    required this.detail,
    this.unit,
    this.fraction,
  });

  final String headline;
  final String value;
  final String? unit;
  final String detail;

  /// Null means the account has no reliable fixed-schedule estimate.
  final double? fraction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4;
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            headline,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 10,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 52,
                  height: 68 / 52,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (unit != null)
                Text(
                  unit!,
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              height: 17 / 12,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 9),
          if (fraction != null)
            Semantics(
              label:
                  'Supply illustration for the estimated $value ${unit ?? 'units'}',
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 196,
                  height: 5,
                  child: Row(
                    children: List.generate(
                      10,
                      (index) => Expanded(
                        child: Container(
                          height: 5,
                          margin: EdgeInsets.only(right: index == 9 ? 0 : 4),
                          decoration: BoxDecoration(
                            color:
                                index < (fraction! * 10).ceil()
                                    ? FardaConsumerColors.warm
                                    : const Color(
                                      0xFFDCE2EB,
                                    ).withValues(alpha: .3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      final vial = ExcludeSemantics(
        child: SvgPicture.asset(
          'assets/figma/vial.svg',
          width: 90,
          height: 140,
        ),
      );
      return FardaSceneCard(
        scene: FardaScene.refills,
        padding: const EdgeInsets.all(20),
        child:
            narrow
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: vial),
                  ],
                )
                : IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 140),
                          child: copy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      vial,
                    ],
                  ),
                ),
      );
    },
  );
}

class RefillsSafetyBanner extends StatelessWidget {
  const RefillsSafetyBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: FardaConsumerColors.warm,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FardaVectorIcon('icon-info', size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Planning only. Your pharmacy confirms eligibility.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              height: 17 / 12,
              color: FardaConsumerColors.textWarm,
            ),
          ),
        ),
      ],
    ),
  );
}

class RefillsPrimaryAction extends StatelessWidget {
  const RefillsPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        backgroundColor: FardaConsumerColors.brand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: FardaConsumerType.bodyStrong,
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

class RefillsJourneyCard extends StatelessWidget {
  const RefillsJourneyCard({
    super.key,
    required this.medicationName,
    required this.pharmacyLabel,
    required this.activeStep,
    this.onOpenDetails,
  });

  final String medicationName;
  final String pharmacyLabel;

  /// 0 means a plan has not been saved; 1-4 are user-reported stages.
  final int activeStep;
  final VoidCallback? onOpenDetails;

  static const _steps = <(String, String)>[
    ('Plan ahead', 'Check your label and details.'),
    ('Contact pharmacy', 'Reach out to your pharmacy.'),
    ('Pharmacy review', 'They confirm timing and eligibility.'),
    ('Receive & add supply', 'Add what you actually receive.'),
  ];

  @override
  Widget build(BuildContext context) => FardaConsumerCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FardaConsumerColors.soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const FardaVectorIcon('icon-pill', size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicationName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FardaConsumerType.bodyStrong,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pharmacyLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FardaConsumerType.caption,
                  ),
                ],
              ),
            ),
            if (onOpenDetails != null)
              IconButton(
                tooltip: 'Review $medicationName',
                onPressed: onOpenDetails,
                icon: const FardaVectorIcon('icon-arrow', size: 16),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: FardaConsumerColors.soft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'SELF-MANAGED',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 10,
              height: 14 / 10,
              fontWeight: FontWeight.w600,
              color: FardaConsumerColors.brand,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _steps.length; index++) ...[
          Semantics(
            label:
                '${_steps[index].$1}, ${index + 1 == activeStep
                    ? 'current step'
                    : index + 1 < activeStep
                    ? 'earlier step'
                    : 'upcoming step'}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        index + 1 <= activeStep
                            ? FardaConsumerColors.brand
                            : FardaConsumerColors.soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      height: 17 / 12,
                      fontWeight: FontWeight.w600,
                      color:
                          index + 1 <= activeStep
                              ? Colors.white
                              : FardaConsumerColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[index].$1,
                        style: FardaConsumerType.bodyStrong,
                      ),
                      const SizedBox(height: 3),
                      Text(_steps[index].$2, style: FardaConsumerType.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (index != _steps.length - 1) const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
