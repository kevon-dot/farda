part of '_components.dart';

class PhoneNumberInput extends StatefulWidget {
  final Function(String)? onPhoneNumberChanged;
  final Function(Country)? onCountryChanged;
  final String? initialPhoneNumber;
  final Country? initialCountry;
  final String? hintText;
  final TextStyle? textStyle;
  final InputDecoration? decoration;

  const PhoneNumberInput({
    super.key,
    this.onPhoneNumberChanged,
    this.onCountryChanged,
    this.initialPhoneNumber,
    this.initialCountry,
    this.hintText = 'Mobile number',
    this.textStyle,
    this.decoration,
  });

  @override
  State<PhoneNumberInput> createState() => _PhoneNumberInputState();
}

class _PhoneNumberInputState extends State<PhoneNumberInput> {
  late TextEditingController _phoneController;
  late Country _selectedCountry;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text: widget.initialPhoneNumber ?? '',
    );
    _selectedCountry = widget.initialCountry ?? _countries.first;
    _phoneController.addListener(_onPhoneNumberChanged);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onPhoneNumberChanged() {
    if (widget.onPhoneNumberChanged != null) {
      widget.onPhoneNumberChanged!(_phoneController.text);
    }
  }

  void _onCountryChanged(Country country) {
    setState(() {
      _selectedCountry = country;
    });
    if (widget.onCountryChanged != null) {
      widget.onCountryChanged!(country);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Country Dropdown
          InkWell(
            onTap: _showCountryPicker,
            child: Container(
              padding: const EdgeInsets.all(13.0).w,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: colors.slate.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCountry.flag,
                    style: TextStyle(fontSize: 20.sp),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down, color: colors.slate.shade700),
                ],
              ),
            ),
          ),
          12.horizontalSpace,
          // Phone Number Input
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: (widget.textStyle ?? theme.textTheme.bodyLarge)?.copyWith(
                color: colors.baseBlack,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: colors.slate.shade300),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(right: 6.w, left: 12.w),
                  child: Text(
                    _selectedCountry.dialCode,
                    style: TextStyle(
                      color: colors.baseBlack,
                      fontWeight: FontWeight.w400,
                      fontSize: (widget.textStyle ?? theme.textTheme.bodyLarge)?.fontSize,
                    ),
                  ),
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: 60.w,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Country',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _countries.length,
                  itemBuilder: (context, index) {
                    final country = _countries[index];
                    return ListTile(
                      leading: Text(
                        country.flag,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(country.name),
                      trailing: Text(
                        country.dialCode,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        _onCountryChanged(country);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
