part of './_components.dart';

class Country {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });
}

String getCurrentDate() {
  // Get the current date as a DateTime object
  DateTime now = DateTime.now();

  // Format the date as 'yyyy-MM-dd'
  String formattedDate = DateFormat('yyyy-MM-dd').format(now);

  return formattedDate;
}

final List<Country> _countries = [
  Country(name: 'Afghanistan', code: 'AF', dialCode: '+93', flag: '🇦🇫'),
  Country(name: 'Albania', code: 'AL', dialCode: '+355', flag: '🇦🇱'),
  Country(name: 'Algeria', code: 'DZ', dialCode: '+213', flag: '🇩🇿'),
  Country(name: 'American Samoa', code: 'AS', dialCode: '+1684', flag: '🇦🇸'),
  Country(name: 'Andorra', code: 'AD', dialCode: '+376', flag: '🇦🇩'),
  Country(name: 'Angola', code: 'AO', dialCode: '+244', flag: '🇦🇴'),
  Country(name: 'Anguilla', code: 'AI', dialCode: '+1264', flag: '🇦🇮'),
  Country(name: 'Antarctica', code: 'AQ', dialCode: '+672', flag: '🇦🇶'),
  Country(
    name: 'Antigua and Barbuda',
    code: 'AG',
    dialCode: '+1268',
    flag: '🇦🇬',
  ),
  Country(name: 'Argentina', code: 'AR', dialCode: '+54', flag: '🇦🇷'),
  Country(name: 'Armenia', code: 'AM', dialCode: '+374', flag: '🇦🇲'),
  Country(name: 'Aruba', code: 'AW', dialCode: '+297', flag: '🇦🇼'),
  Country(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
  Country(name: 'Austria', code: 'AT', dialCode: '+43', flag: '🇦🇹'),
  Country(name: 'Azerbaijan', code: 'AZ', dialCode: '+994', flag: '🇦🇿'),
  Country(name: 'Bahamas', code: 'BS', dialCode: '+1242', flag: '🇧🇸'),
  Country(name: 'Bahrain', code: 'BH', dialCode: '+973', flag: '🇧🇭'),
  Country(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩'),
  Country(name: 'Barbados', code: 'BB', dialCode: '+1246', flag: '🇧🇧'),
  Country(name: 'Belarus', code: 'BY', dialCode: '+375', flag: '🇧🇾'),
  Country(name: 'Belgium', code: 'BE', dialCode: '+32', flag: '🇧🇪'),
  Country(name: 'Belize', code: 'BZ', dialCode: '+501', flag: '🇧🇿'),
  Country(name: 'Benin', code: 'BJ', dialCode: '+229', flag: '🇧🇯'),
  Country(name: 'Bermuda', code: 'BM', dialCode: '+1441', flag: '🇧🇲'),
  Country(name: 'Bhutan', code: 'BT', dialCode: '+975', flag: '🇧🇹'),
  Country(name: 'Bolivia', code: 'BO', dialCode: '+591', flag: '🇧🇴'),
  Country(
    name: 'Bosnia and Herzegovina',
    code: 'BA',
    dialCode: '+387',
    flag: '🇧🇦',
  ),
  Country(name: 'Botswana', code: 'BW', dialCode: '+267', flag: '🇧🇼'),
  Country(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
  Country(
    name: 'British Indian Ocean Territory',
    code: 'IO',
    dialCode: '+246',
    flag: '🇮🇴',
  ),
  Country(
    name: 'British Virgin Islands',
    code: 'VG',
    dialCode: '+1284',
    flag: '🇻🇬',
  ),
  Country(name: 'Brunei', code: 'BN', dialCode: '+673', flag: '🇧🇳'),
  Country(name: 'Bulgaria', code: 'BG', dialCode: '+359', flag: '🇧🇬'),
  Country(name: 'Burkina Faso', code: 'BF', dialCode: '+226', flag: '🇧🇫'),
  Country(name: 'Burundi', code: 'BI', dialCode: '+257', flag: '🇧🇮'),
  Country(name: 'Cambodia', code: 'KH', dialCode: '+855', flag: '🇰🇭'),
  Country(name: 'Cameroon', code: 'CM', dialCode: '+237', flag: '🇨🇲'),
  Country(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
  Country(name: 'Cape Verde', code: 'CV', dialCode: '+238', flag: '🇨🇻'),
  Country(name: 'Cayman Islands', code: 'KY', dialCode: '+1345', flag: '🇰🇾'),
  Country(
    name: 'Central African Republic',
    code: 'CF',
    dialCode: '+236',
    flag: '🇨🇫',
  ),
  Country(name: 'Chad', code: 'TD', dialCode: '+235', flag: '🇹🇩'),
  Country(name: 'Chile', code: 'CL', dialCode: '+56', flag: '🇨🇱'),
  Country(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
  Country(name: 'Christmas Island', code: 'CX', dialCode: '+61', flag: '🇨🇽'),
  Country(name: 'Cocos Islands', code: 'CC', dialCode: '+61', flag: '🇨🇨'),
  Country(name: 'Colombia', code: 'CO', dialCode: '+57', flag: '🇨🇴'),
  Country(name: 'Comoros', code: 'KM', dialCode: '+269', flag: '🇰🇲'),
  Country(name: 'Congo', code: 'CG', dialCode: '+242', flag: '🇨🇬'),
  Country(
    name: 'Congo (Democratic Republic)',
    code: 'CD',
    dialCode: '+243',
    flag: '🇨🇩',
  ),
  Country(name: 'Cook Islands', code: 'CK', dialCode: '+682', flag: '🇨🇰'),
  Country(name: 'Costa Rica', code: 'CR', dialCode: '+506', flag: '🇨🇷'),
  Country(name: 'Croatia', code: 'HR', dialCode: '+385', flag: '🇭🇷'),
  Country(name: 'Cuba', code: 'CU', dialCode: '+53', flag: '🇨🇺'),
  Country(name: 'Curacao', code: 'CW', dialCode: '+5999', flag: '🇨🇼'),
  Country(name: 'Cyprus', code: 'CY', dialCode: '+357', flag: '🇨🇾'),
  Country(name: 'Czech Republic', code: 'CZ', dialCode: '+420', flag: '🇨🇿'),
  Country(name: 'Denmark', code: 'DK', dialCode: '+45', flag: '🇩🇰'),
  Country(name: 'Djibouti', code: 'DJ', dialCode: '+253', flag: '🇩🇯'),
  Country(name: 'Dominica', code: 'DM', dialCode: '+1767', flag: '🇩🇲'),
  Country(
    name: 'Dominican Republic',
    code: 'DO',
    dialCode: '+1849',
    flag: '🇩🇴',
  ),
  Country(name: 'Ecuador', code: 'EC', dialCode: '+593', flag: '🇪🇨'),
  Country(name: 'Egypt', code: 'EG', dialCode: '+20', flag: '🇪🇬'),
  Country(name: 'El Salvador', code: 'SV', dialCode: '+503', flag: '🇸🇻'),
  Country(
    name: 'Equatorial Guinea',
    code: 'GQ',
    dialCode: '+240',
    flag: '🇬🇶',
  ),
  Country(name: 'Eritrea', code: 'ER', dialCode: '+291', flag: '🇪🇷'),
  Country(name: 'Estonia', code: 'EE', dialCode: '+372', flag: '🇪🇪'),
  Country(name: 'Ethiopia', code: 'ET', dialCode: '+251', flag: '🇪🇹'),
  Country(name: 'Falkland Islands', code: 'FK', dialCode: '+500', flag: '🇫🇰'),
  Country(name: 'Faroe Islands', code: 'FO', dialCode: '+298', flag: '🇫🇴'),
  Country(name: 'Fiji', code: 'FJ', dialCode: '+679', flag: '🇫🇯'),
  Country(name: 'Finland', code: 'FI', dialCode: '+358', flag: '🇫🇮'),
  Country(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
  Country(name: 'French Guiana', code: 'GF', dialCode: '+594', flag: '🇬🇫'),
  Country(name: 'French Polynesia', code: 'PF', dialCode: '+689', flag: '🇵🇫'),
  Country(name: 'Gabon', code: 'GA', dialCode: '+241', flag: '🇬🇦'),
  Country(name: 'Gambia', code: 'GM', dialCode: '+220', flag: '🇬🇲'),
  Country(name: 'Georgia', code: 'GE', dialCode: '+995', flag: '🇬🇪'),
  Country(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
  Country(name: 'Ghana', code: 'GH', dialCode: '+233', flag: '🇬🇭'),
  Country(name: 'Gibraltar', code: 'GI', dialCode: '+350', flag: '🇬🇮'),
  Country(name: 'Greece', code: 'GR', dialCode: '+30', flag: '🇬🇷'),
  Country(name: 'Greenland', code: 'GL', dialCode: '+299', flag: '🇬🇱'),
  Country(name: 'Grenada', code: 'GD', dialCode: '+1473', flag: '🇬🇩'),
  Country(name: 'Guadeloupe', code: 'GP', dialCode: '+590', flag: '🇬🇵'),
  Country(name: 'Guam', code: 'GU', dialCode: '+1671', flag: '🇬🇺'),
  Country(name: 'Guatemala', code: 'GT', dialCode: '+502', flag: '🇬🇹'),
  Country(name: 'Guernsey', code: 'GG', dialCode: '+44', flag: '🇬🇬'),
  Country(name: 'Guinea', code: 'GN', dialCode: '+224', flag: '🇬🇳'),
  Country(name: 'Guinea-Bissau', code: 'GW', dialCode: '+245', flag: '🇬🇼'),
  Country(name: 'Guyana', code: 'GY', dialCode: '+592', flag: '🇬🇾'),
  Country(name: 'Haiti', code: 'HT', dialCode: '+509', flag: '🇭🇹'),
  Country(name: 'Honduras', code: 'HN', dialCode: '+504', flag: '🇭🇳'),
  Country(name: 'Hong Kong', code: 'HK', dialCode: '+852', flag: '🇭🇰'),
  Country(name: 'Hungary', code: 'HU', dialCode: '+36', flag: '🇭🇺'),
  Country(name: 'Iceland', code: 'IS', dialCode: '+354', flag: '🇮🇸'),
  Country(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
  Country(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
  Country(name: 'Iran', code: 'IR', dialCode: '+98', flag: '🇮🇷'),
  Country(name: 'Iraq', code: 'IQ', dialCode: '+964', flag: '🇮🇶'),
  Country(name: 'Ireland', code: 'IE', dialCode: '+353', flag: '🇮🇪'),
  Country(name: 'Isle of Man', code: 'IM', dialCode: '+44', flag: '🇮🇲'),
  Country(name: 'Israel', code: 'IL', dialCode: '+972', flag: '🇮🇱'),
  Country(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
  Country(name: 'Ivory Coast', code: 'CI', dialCode: '+225', flag: '🇨🇮'),
  Country(name: 'Jamaica', code: 'JM', dialCode: '+1876', flag: '🇯🇲'),
  Country(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
  Country(name: 'Jersey', code: 'JE', dialCode: '+44', flag: '🇯🇪'),
  Country(name: 'Jordan', code: 'JO', dialCode: '+962', flag: '🇯🇴'),
  Country(name: 'Kazakhstan', code: 'KZ', dialCode: '+7', flag: '🇰🇿'),
  Country(name: 'Kenya', code: 'KE', dialCode: '+254', flag: '🇰🇪'),
  Country(name: 'Kiribati', code: 'KI', dialCode: '+686', flag: '🇰🇮'),
  Country(name: 'Kosovo', code: 'XK', dialCode: '+383', flag: '🇽🇰'),
  Country(name: 'Kuwait', code: 'KW', dialCode: '+965', flag: '🇰🇼'),
  Country(name: 'Kyrgyzstan', code: 'KG', dialCode: '+996', flag: '🇰🇬'),
  Country(name: 'Laos', code: 'LA', dialCode: '+856', flag: '🇱🇦'),
  Country(name: 'Latvia', code: 'LV', dialCode: '+371', flag: '🇱🇻'),
  Country(name: 'Lebanon', code: 'LB', dialCode: '+961', flag: '🇱🇧'),
  Country(name: 'Lesotho', code: 'LS', dialCode: '+266', flag: '🇱🇸'),
  Country(name: 'Liberia', code: 'LR', dialCode: '+231', flag: '🇱🇷'),
  Country(name: 'Libya', code: 'LY', dialCode: '+218', flag: '🇱🇾'),
  Country(name: 'Liechtenstein', code: 'LI', dialCode: '+423', flag: '🇱🇮'),
  Country(name: 'Lithuania', code: 'LT', dialCode: '+370', flag: '🇱🇹'),
  Country(name: 'Luxembourg', code: 'LU', dialCode: '+352', flag: '🇱🇺'),
  Country(name: 'Macao', code: 'MO', dialCode: '+853', flag: '🇲🇴'),
  Country(name: 'Macedonia', code: 'MK', dialCode: '+389', flag: '🇲🇰'),
  Country(name: 'Madagascar', code: 'MG', dialCode: '+261', flag: '🇲🇬'),
  Country(name: 'Malawi', code: 'MW', dialCode: '+265', flag: '🇲🇼'),
  Country(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
  Country(name: 'Maldives', code: 'MV', dialCode: '+960', flag: '🇲🇻'),
  Country(name: 'Mali', code: 'ML', dialCode: '+223', flag: '🇲🇱'),
  Country(name: 'Malta', code: 'MT', dialCode: '+356', flag: '🇲🇹'),
  Country(name: 'Marshall Islands', code: 'MH', dialCode: '+692', flag: '🇲🇭'),
  Country(name: 'Martinique', code: 'MQ', dialCode: '+596', flag: '🇲🇶'),
  Country(name: 'Mauritania', code: 'MR', dialCode: '+222', flag: '🇲🇷'),
  Country(name: 'Mauritius', code: 'MU', dialCode: '+230', flag: '🇲🇺'),
  Country(name: 'Mayotte', code: 'YT', dialCode: '+262', flag: '🇾🇹'),
  Country(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽'),
  Country(name: 'Micronesia', code: 'FM', dialCode: '+691', flag: '🇫🇲'),
  Country(name: 'Moldova', code: 'MD', dialCode: '+373', flag: '🇲🇩'),
  Country(name: 'Monaco', code: 'MC', dialCode: '+377', flag: '🇲🇨'),
  Country(name: 'Mongolia', code: 'MN', dialCode: '+976', flag: '🇲🇳'),
  Country(name: 'Montenegro', code: 'ME', dialCode: '+382', flag: '🇲🇪'),
  Country(name: 'Montserrat', code: 'MS', dialCode: '+1664', flag: '🇲🇸'),
  Country(name: 'Morocco', code: 'MA', dialCode: '+212', flag: '🇲🇦'),
  Country(name: 'Mozambique', code: 'MZ', dialCode: '+258', flag: '🇲🇿'),
  Country(name: 'Myanmar', code: 'MM', dialCode: '+95', flag: '🇲🇲'),
  Country(name: 'Namibia', code: 'NA', dialCode: '+264', flag: '🇳🇦'),
  Country(name: 'Nauru', code: 'NR', dialCode: '+674', flag: '🇳🇷'),
  Country(name: 'Nepal', code: 'NP', dialCode: '+977', flag: '🇳🇵'),
  Country(name: 'Netherlands', code: 'NL', dialCode: '+31', flag: '🇳🇱'),
  Country(name: 'New Caledonia', code: 'NC', dialCode: '+687', flag: '🇳🇨'),
  Country(name: 'New Zealand', code: 'NZ', dialCode: '+64', flag: '🇳🇿'),
  Country(name: 'Nicaragua', code: 'NI', dialCode: '+505', flag: '🇳🇮'),
  Country(name: 'Niger', code: 'NE', dialCode: '+227', flag: '🇳🇪'),
  Country(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬'),
  Country(name: 'Niue', code: 'NU', dialCode: '+683', flag: '🇳🇺'),
  Country(name: 'Norfolk Island', code: 'NF', dialCode: '+672', flag: '🇳🇫'),
  Country(name: 'North Korea', code: 'KP', dialCode: '+850', flag: '🇰🇵'),
  Country(
    name: 'Northern Mariana Islands',
    code: 'MP',
    dialCode: '+1670',
    flag: '🇲🇵',
  ),
  Country(name: 'Norway', code: 'NO', dialCode: '+47', flag: '🇳🇴'),
  Country(name: 'Oman', code: 'OM', dialCode: '+968', flag: '🇴🇲'),
  Country(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰'),
  Country(name: 'Palau', code: 'PW', dialCode: '+680', flag: '🇵🇼'),
  Country(name: 'Palestine', code: 'PS', dialCode: '+970', flag: '🇵🇸'),
  Country(name: 'Panama', code: 'PA', dialCode: '+507', flag: '🇵🇦'),
  Country(name: 'Papua New Guinea', code: 'PG', dialCode: '+675', flag: '🇵🇬'),
  Country(name: 'Paraguay', code: 'PY', dialCode: '+595', flag: '🇵🇾'),
  Country(name: 'Peru', code: 'PE', dialCode: '+51', flag: '🇵🇪'),
  Country(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
  Country(name: 'Pitcairn', code: 'PN', dialCode: '+64', flag: '🇵🇳'),
  Country(name: 'Poland', code: 'PL', dialCode: '+48', flag: '🇵🇱'),
  Country(name: 'Portugal', code: 'PT', dialCode: '+351', flag: '🇵🇹'),
  Country(name: 'Puerto Rico', code: 'PR', dialCode: '+1939', flag: '🇵🇷'),
  Country(name: 'Qatar', code: 'QA', dialCode: '+974', flag: '🇶🇦'),
  Country(name: 'Reunion', code: 'RE', dialCode: '+262', flag: '🇷🇪'),
  Country(name: 'Romania', code: 'RO', dialCode: '+40', flag: '🇷🇴'),
  Country(name: 'Russia', code: 'RU', dialCode: '+7', flag: '🇷🇺'),
  Country(name: 'Rwanda', code: 'RW', dialCode: '+250', flag: '🇷🇼'),
  Country(name: 'Saint Barthelemy', code: 'BL', dialCode: '+590', flag: '🇧🇱'),
  Country(name: 'Saint Helena', code: 'SH', dialCode: '+290', flag: '🇸🇭'),
  Country(
    name: 'Saint Kitts and Nevis',
    code: 'KN',
    dialCode: '+1869',
    flag: '🇰🇳',
  ),
  Country(name: 'Saint Lucia', code: 'LC', dialCode: '+1758', flag: '🇱🇨'),
  Country(name: 'Saint Martin', code: 'MF', dialCode: '+590', flag: '🇲🇫'),
  Country(
    name: 'Saint Pierre and Miquelon',
    code: 'PM',
    dialCode: '+508',
    flag: '🇵🇲',
  ),
  Country(
    name: 'Saint Vincent and the Grenadines',
    code: 'VC',
    dialCode: '+1784',
    flag: '🇻🇨',
  ),
  Country(name: 'Samoa', code: 'WS', dialCode: '+685', flag: '🇼🇸'),
  Country(name: 'San Marino', code: 'SM', dialCode: '+378', flag: '🇸🇲'),
  Country(
    name: 'Sao Tome and Principe',
    code: 'ST',
    dialCode: '+239',
    flag: '🇸🇹',
  ),
  Country(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
  Country(name: 'Senegal', code: 'SN', dialCode: '+221', flag: '🇸🇳'),
  Country(name: 'Serbia', code: 'RS', dialCode: '+381', flag: '🇷🇸'),
  Country(name: 'Seychelles', code: 'SC', dialCode: '+248', flag: '🇸🇨'),
  Country(name: 'Sierra Leone', code: 'SL', dialCode: '+232', flag: '🇸🇱'),
  Country(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
  Country(name: 'Sint Maarten', code: 'SX', dialCode: '+1721', flag: '🇸🇽'),
  Country(name: 'Slovakia', code: 'SK', dialCode: '+421', flag: '🇸🇰'),
  Country(name: 'Slovenia', code: 'SI', dialCode: '+386', flag: '🇸🇮'),
  Country(name: 'Solomon Islands', code: 'SB', dialCode: '+677', flag: '🇸🇧'),
  Country(name: 'Somalia', code: 'SO', dialCode: '+252', flag: '🇸🇴'),
  Country(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
  Country(
    name: 'South Georgia and the South Sandwich Islands',
    code: 'GS',
    dialCode: '+500',
    flag: '🇬🇸',
  ),
  Country(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
  Country(name: 'South Sudan', code: 'SS', dialCode: '+211', flag: '🇸🇸'),
  Country(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
  Country(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰'),
  Country(name: 'Sudan', code: 'SD', dialCode: '+249', flag: '🇸🇩'),
  Country(name: 'Suriname', code: 'SR', dialCode: '+597', flag: '🇸🇷'),
  Country(
    name: 'Svalbard and Jan Mayen',
    code: 'SJ',
    dialCode: '+47',
    flag: '🇸🇯',
  ),
  Country(name: 'Swaziland', code: 'SZ', dialCode: '+268', flag: '🇸🇿'),
  Country(name: 'Sweden', code: 'SE', dialCode: '+46', flag: '🇸🇪'),
  Country(name: 'Switzerland', code: 'CH', dialCode: '+41', flag: '🇨🇭'),
  Country(name: 'Syria', code: 'SY', dialCode: '+963', flag: '🇸🇾'),
  Country(name: 'Taiwan', code: 'TW', dialCode: '+886', flag: '🇹🇼'),
  Country(name: 'Tajikistan', code: 'TJ', dialCode: '+992', flag: '🇹🇯'),
  Country(name: 'Tanzania', code: 'TZ', dialCode: '+255', flag: '🇹🇿'),
  Country(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭'),
  Country(name: 'Timor-Leste', code: 'TL', dialCode: '+670', flag: '🇹🇱'),
  Country(name: 'Togo', code: 'TG', dialCode: '+228', flag: '🇹🇬'),
  Country(name: 'Tokelau', code: 'TK', dialCode: '+690', flag: '🇹🇰'),
  Country(name: 'Tonga', code: 'TO', dialCode: '+676', flag: '🇹🇴'),
  Country(
    name: 'Trinidad and Tobago',
    code: 'TT',
    dialCode: '+1868',
    flag: '🇹🇹',
  ),
  Country(name: 'Tunisia', code: 'TN', dialCode: '+216', flag: '🇹🇳'),
  Country(name: 'Turkey', code: 'TR', dialCode: '+90', flag: '🇹🇷'),
  Country(name: 'Turkmenistan', code: 'TM', dialCode: '+993', flag: '🇹🇲'),
  Country(
    name: 'Turks and Caicos Islands',
    code: 'TC',
    dialCode: '+1649',
    flag: '🇹🇨',
  ),
  Country(name: 'Tuvalu', code: 'TV', dialCode: '+688', flag: '🇹🇻'),
  Country(
    name: 'U.S. Virgin Islands',
    code: 'VI',
    dialCode: '+1340',
    flag: '🇻🇮',
  ),
  Country(name: 'Uganda', code: 'UG', dialCode: '+256', flag: '🇺🇬'),
  Country(name: 'Ukraine', code: 'UA', dialCode: '+380', flag: '🇺🇦'),
  Country(
    name: 'United Arab Emirates',
    code: 'AE',
    dialCode: '+971',
    flag: '🇦🇪',
  ),
  Country(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
  Country(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  Country(
    name: 'United States Minor Outlying Islands',
    code: 'UM',
    dialCode: '+1',
    flag: '🇺🇲',
  ),
  Country(name: 'Uruguay', code: 'UY', dialCode: '+598', flag: '🇺🇾'),
  Country(name: 'Uzbekistan', code: 'UZ', dialCode: '+998', flag: '🇺🇿'),
  Country(name: 'Vanuatu', code: 'VU', dialCode: '+678', flag: '🇻🇺'),
  Country(name: 'Vatican', code: 'VA', dialCode: '+379', flag: '🇻🇦'),
  Country(name: 'Venezuela', code: 'VE', dialCode: '+58', flag: '🇻🇪'),
  Country(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳'),
  Country(
    name: 'Wallis and Futuna',
    code: 'WF',
    dialCode: '+681',
    flag: '🇼🇫',
  ),
  Country(name: 'Western Sahara', code: 'EH', dialCode: '+212', flag: '🇪🇭'),
  Country(name: 'Yemen', code: 'YE', dialCode: '+967', flag: '🇾🇪'),
  Country(name: 'Zambia', code: 'ZM', dialCode: '+260', flag: '🇿🇲'),
  Country(name: 'Zimbabwe', code: 'ZW', dialCode: '+263', flag: '🇿🇼'),
];

class PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String originalPrice;
  final String billingInfo;
  final bool isSelected;
  final VoidCallback? onTap;

  const PricingCard({
    super.key,
    required this.title,
    required this.price,
    required this.period,
    required this.originalPrice,
    required this.billingInfo,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FardaColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180.h,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colors.success[25] : Colors.white,
          border: Border.all(
            color: isSelected ? colors.success[500]! : colors.slate.shade100,
            width: 1.r,
          ),
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              offset: Offset(0, 2),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: colors.baseBlack,
                  ),
                ),
                Container(
                  width: 20.h,
                  height: 20.h,
                  decoration: BoxDecoration(
                    color: colors.success[500],
                    shape: BoxShape.circle,
                  ),
                  child:
                      isSelected
                          ? Icon(
                            Icons.check,
                            color: colors.baseWhite,
                            size: 14.h,
                          )
                          : Container(
                            decoration: BoxDecoration(
                              color: colors.baseWhite,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.slate.shade200),
                            ),
                          ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: colors.slate.shade600,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(fontSize: 12, color: colors.slate.shade600),
                ),
              ],
            ),
            Text(
              originalPrice,
              style: TextStyle(
                fontSize: 12.sp,
                color: colors.slate.shade600,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            12.verticalSpace,
            Text(
              billingInfo,
              style: TextStyle(fontSize: 12.sp, color: colors.slate.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class WeekCalendar extends StatefulWidget {
  final Function(DateTime date) onDateSelected;

  const WeekCalendar({super.key, required this.onDateSelected});

  @override
  State<WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<WeekCalendar> {
  late List<DateTime> weekDates;
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
    weekDates = _getCurrentWeekDates(selectedDate);
  }

  List<DateTime> _getCurrentWeekDates(DateTime currentDate) {
    int currentWeekday = currentDate.weekday % 7; // Make Sunday = 0
    DateTime sunday = currentDate.subtract(Duration(days: currentWeekday));
    return List.generate(7, (index) => sunday.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:
            weekDates.map((date) {
              final isSelected = DateUtils.isSameDay(date, selectedDate);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.xs),
                child: GestureDetector(
                  onTap: () {
                    widget.onDateSelected(date);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ).r,
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Colors.transparent
                              : colors.slate.shade100,
                      borderRadius: BorderRadius.circular(24).r,
                      border: Border.all(
                        color:
                            isSelected
                                ? colors.slate.shade200
                                : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? colors.baseBlack
                                    : colors.slate.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            DateFormat.E().format(
                              date,
                            )[0], // First letter of weekday
                            style: TextStyle(
                              fontSize: 14.sp,
                              color:
                                  isSelected
                                      ? colors.baseWhite
                                      : colors.slate.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: 14.sp,
                            color:
                                isSelected
                                    ? colors.baseBlack
                                    : colors.slate.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

/// ****************************************************************************
/// Statistic progressbar
/// ****************************************************************************
class HalfCircularProgressBar extends StatefulWidget {
  final double maxValue;
  final double progressValue;
  final double size;
  final Widget child;

  const HalfCircularProgressBar({
    super.key,
    required this.maxValue,
    required this.progressValue,
    required this.child,
    this.size = 140,
  });

  @override
  State<HalfCircularProgressBar> createState() =>
      _HalfCircularProgressBarState();
}

class _HalfCircularProgressBarState extends State<HalfCircularProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
  }

  void _initAnimation() {
    final percentage = (widget.progressValue / widget.maxValue).clamp(0.0, 1.0);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: percentage,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(HalfCircularProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressValue != widget.progressValue ||
        oldWidget.maxValue != widget.maxValue) {
      _controller.dispose();
      _initAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _progressAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: _HalfCirclePainter(
              progress: _progressAnimation.value,
              backgroundColor: colors.slate.shade100,
              progressColor: colors.blue,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _HalfCirclePainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _HalfCirclePainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    this.strokeWidth = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final startAngle = 3 * pi / 4; // 135 degrees
    final sweepAngle = 1.5 * pi; // 45 degrees

    final Paint bgPaint =
        Paint()
          ..color = backgroundColor
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final Paint progressPaint =
        Paint()
          ..color = progressColor
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      startAngle,
      sweepAngle * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// ****************************************************************************
/// Prescription
/// ****************************************************************************
class PrescriptionView extends StatelessWidget {
  final String drName;
  final String address;
  final String patientName;
  final String rxNumber;
  final String storeNumber;
  final String title;
  final String description;
  final String quantity;
  final String? notification;
  final String? sideEffects;
  final VoidCallback? onSetupVial;

  const PrescriptionView({
    super.key,
    required this.drName,
    required this.address,
    required this.patientName,
    required this.rxNumber,
    required this.storeNumber,
    required this.title,
    required this.description,
    required this.quantity,
    this.notification,
    this.sideEffects,
    this.onSetupVial,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        border: Border.all(color: colors.slate.shade200),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                height: 40.h,
                width: 40.h,
                child: Center(child: SvgPicture.asset("assets/icons/rx.svg")),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(drName, style: theme.textTheme.bodyLarge),
                    Text(address, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          12.verticalSpace,
          Container(
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              border: Border.all(color: colors.slate.shade200),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                4.verticalSpace,
                Container(
                  padding: EdgeInsets.all(6.r),
                  decoration: BoxDecoration(
                    color: colors.warning[50],
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "RX Number:",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.slate.shade600,
                        ),
                      ),
                      Text(
                        rxNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.error[500],
                        ),
                      ),
                    ],
                  ),
                ),
                4.verticalSpace,
                Container(
                  padding: EdgeInsets.all(6.r),
                  decoration: BoxDecoration(
                    color: colors.warning[50],
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Store Number:",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.slate.shade600,
                        ),
                      ),
                      Text(
                        storeNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.error[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          12.verticalSpace,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 16.sp,
                      ),
                    ),
                    8.verticalSpace,
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.slate.shade600,
                      ),
                    ),
                    8.verticalSpace,
                    Text(
                      "Qty: $quantity",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.slate.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSetupVial != null)
                IconButton(
                  onPressed: onSetupVial,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.primaryColor.withOpacity(0.1),
                  ),
                  icon: Icon(
                    Icons.bluetooth_connected,
                    color: theme.primaryColor,
                    size: 20.r,
                  ),
                  tooltip: 'Setup Vial',
                ),
            ],
          ),
          if (notification != null) 8.verticalSpace,
          if (notification != null)
            Text(
              notification!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.slate.shade600,
              ),
            ),
          if (sideEffects != null) 8.verticalSpace,
          if (sideEffects != null)
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                color: colors.slate.shade100,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Side Effects:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.slate.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                    ),
                  ),
                  8.verticalSpace,
                  Text(
                    sideEffects!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.slate.shade600,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// ****************************************************************************
/// Progress section
/// ****************************************************************************
class PillProgressSection extends StatelessWidget {
  final String remainingLabel;
  final String remainingValue;
  final String consumedLabel;
  final double consumedValue;
  final double consumedMax;
  final String targetLabel;
  final String targetValue;

  const PillProgressSection({
    super.key,
    this.remainingLabel = "Remaining",
    required this.remainingValue,
    this.consumedLabel = "Consumed",
    required this.consumedValue,
    required this.consumedMax,
    this.targetLabel = "Target",
    required this.targetValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 25,
          child: _countWidget(
            context,
            title: remainingLabel,
            value: remainingValue,
            fontFactor: 0.8,
          ),
        ),
        Expanded(
          flex: 50,
          child: Center(
            child: HalfCircularProgressBar(
              maxValue: consumedMax,
              progressValue: consumedValue,
              child: _countWidget(
                context,
                title: consumedLabel,
                value: consumedValue.toInt().toString(),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 25,
          child: _countWidget(
            context,
            title: targetLabel,
            value: targetValue,
            fontFactor: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _countWidget(
    context, {
    required String title,
    required String value,
    double fontFactor = 1.0,
  }) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 30.sp * fontFactor,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: colors.slate.shade600,
                fontSize: 18.sp * fontFactor,
                height: 1.0,
              ),
            ),
            // important to have a gap under
            const Text("", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// ****************************************************************************
/// Custom calendar
/// ****************************************************************************

class DateHolder extends ChangeNotifier {
  DateTime _value;

  DateHolder(this._value);

  DateTime get value => _value;

  // Use this to update, optionally notifying listeners
  void set(DateTime newValue, {bool notify = true}) {
    _value = newValue;
    if (notify) notifyListeners();
  }
}

enum CalendarEventFrom { dateHeader, infinitePageView }

class CalendarController {
  final ValueNotifier<Map<String, List<CalendarEvent>>> events = ValueNotifier(
    {},
  );

  final DateHolder _selectedDate = DateHolder(DateTime.now());

  DateTime get selectedDate => _selectedDate.value;

  bool _swipingByUser = true;
  int currentPage = 0;

  void selectDate(DateTime date, {bool notify = true}) {
    _selectedDate.set(date, notify: notify);
  }

  void onSwipePage(int index) {
    print(_swipingByUser);
    if (!_swipingByUser) {
      return;
    }
    DateTime newDate = _selectedDate.value;
    final isForward = _isSwipeForward(currentPage, index);
    if (isForward != null) {
      if (isForward) {
        newDate = newDate.add(Duration(days: 1));
      } else {
        newDate = newDate.add(Duration(days: -1));
      }
      _selectedDate.set(newDate, notify: true);
    }
    currentPage = index;
  }

  bool? _isSwipeForward(int prevIndex, int newIndex) {
    if (prevIndex == newIndex) return null;
    if (prevIndex == 2 && newIndex == 0) return true;
    if (prevIndex == 0 && newIndex == 2) return false;
    if (prevIndex > newIndex) return false;
    return (prevIndex + 1) == newIndex;
  }

  void setEvents(Map<String, List<CalendarEvent>> newEvents) {
    events.value = newEvents;
  }
}

// Style configuration
class CalendarStyle {
  final Color currentTimeColor;
  final Color borderColor;
  final Color currentDateColor;
  final Color selectedDateTextColor;
  final Color selectedDateColor;
  final Color currentDateTextColor;
  final double borderWidth;

  const CalendarStyle({
    this.borderColor = const Color(0xFFE0E0E0),
    this.currentTimeColor = Colors.black,
    this.currentDateColor = Colors.blue,
    this.selectedDateTextColor = Colors.white,
    this.selectedDateColor = Colors.blue,
    this.currentDateTextColor = Colors.white,
    this.borderWidth = 1.0,
  });
}

class CustomCalendarView extends StatefulWidget {
  final CalendarController? controller;
  final CalendarStyle style;

  const CustomCalendarView({
    super.key,
    this.controller,
    this.style = const CalendarStyle(),
  });

  @override
  State<CustomCalendarView> createState() => _CustomCalendarViewState();
}

class _CustomCalendarViewState extends State<CustomCalendarView> {
  late PageController _weekPageController;
  late InfiniteScrollController _infiniteScrollController;
  late CalendarController _controller;
  DateTime _currentWeekStart = DateTime.now();

  Map<String, List<CalendarEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? CalendarController();
    _currentWeekStart = _getWeekStart(_controller.selectedDate);
    _weekPageController = PageController(initialPage: 1000);
    _infiniteScrollController = InfiniteScrollController();

    _controller._selectedDate.addListener(_onControllerDateChanged);
    _controller.events.addListener(_onControllerEventsChange);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller._selectedDate.removeListener(_onControllerDateChanged);
      _controller.events.removeListener(_onControllerEventsChange);
      _controller._selectedDate.dispose();
      _controller.events.dispose();
    } else {
      _controller._selectedDate.removeListener(_onControllerDateChanged);
      _controller.events.removeListener(_onControllerEventsChange);
    }
    _weekPageController.dispose();
    super.dispose();
  }

  void _onControllerDateChanged() {
    setState(() {
      // Update week if focus date is not in current week
      final currentWeekDates = _getWeekDates(_currentWeekStart);
      if (!currentWeekDates.any(
        (date) =>
            date.year == _controller.selectedDate.year &&
            date.month == _controller.selectedDate.month &&
            date.day == _controller.selectedDate.day,
      )) {
        _currentWeekStart = _getWeekStart(_controller.selectedDate);
      }
    });
  }

  void _onControllerEventsChange() {
    setState(() {
      _events = _controller.events.value;
    });
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<DateTime> _getWeekDates(DateTime weekStart) {
    return List.generate(7, (index) => weekStart.add(Duration(days: index)));
  }

  void _onWeekChanged(int index) {
    final weekOffset = index - 1000;
    final newWeekStart = _getWeekStart(
      DateTime.now(),
    ).add(Duration(days: weekOffset * 7));

    setState(() {
      _currentWeekStart = newWeekStart;
    });
  }

  void _onDateSelect(DateTime date) async {
    final previousDate = _controller.selectedDate;
    _controller.selectDate(date, notify: false);

    if (date.isBefore(previousDate)) {
      _controller._swipingByUser = false;
      await _infiniteScrollController.previousItem();
      _controller._swipingByUser = true;
    } else if (date.isAfter(previousDate)) {
      _controller._swipingByUser = false;
      await _infiniteScrollController.nextItem();
      _controller._swipingByUser = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dayWidth = screenWidth / 7;
    final currentInMinute = DateTime.now().hour * 60.0 + DateTime.now().minute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Month and Year Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12).r,
          child: Text(
            DateFormat('MMMM yyyy').format(_controller.selectedDate),
            style: Theme.of(context).textTheme.titleLarge?.merge(
              TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // Week Calendar Header
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: widget.style.borderColor,
                width: widget.style.borderWidth,
              ),
            ),
          ),
          height: 80,
          child: PageView.builder(
            controller: _weekPageController,
            onPageChanged: _onWeekChanged,
            itemBuilder: (context, index) {
              final weekOffset = index - 1000;
              final weekStart = _getWeekStart(
                _currentWeekStart,
              ).add(Duration(days: weekOffset * 7));
              final weekDates = _getWeekDates(weekStart);

              return Row(
                children:
                    weekDates.asMap().entries.map((entry) {
                      final dayIndex = entry.key;
                      final date = entry.value;
                      final isSelected =
                          date.year == _controller.selectedDate.year &&
                          date.month == _controller.selectedDate.month &&
                          date.day == _controller.selectedDate.day;
                      final isToday =
                          date.year == DateTime.now().year &&
                          date.month == DateTime.now().month &&
                          date.day == DateTime.now().day;

                      Color circleColor = Colors.transparent;
                      Color textColor = Colors.black87;
                      Color weekTextColor = Colors.grey[600]!;

                      if (isSelected) {
                        circleColor = widget.style.selectedDateColor;
                        textColor = widget.style.selectedDateTextColor;
                      } else if (isToday) {
                        circleColor = widget.style.currentDateColor.withValues(
                          alpha: isSelected ? 1.0 : 0.3,
                        );
                        textColor = widget.style.currentDateTextColor;
                      }

                      return Container(
                        width: dayWidth,
                        decoration: BoxDecoration(
                          border:
                              dayIndex < 6
                                  ? Border(
                                    right: BorderSide(
                                      color: widget.style.borderColor,
                                      width: widget.style.borderWidth,
                                    ),
                                  )
                                  : null,
                        ),
                        child: GestureDetector(
                          onTap: () => _onDateSelect(date),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('E').format(date),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: weekTextColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: circleColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    date.day.toString(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color:
                                          circleColor == Colors.transparent
                                              ? Colors.black87
                                              : textColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ),

        // Time Slots Body
        Expanded(
          child: InfiniteCarousel.builder(
            itemCount: 3,
            itemExtent: 1.0.sw,
            center: true,
            anchor: 0.0,
            velocityFactor: 0.2,
            onIndexChanged: (index) {
              _controller.onSwipePage.call(index);
            },
            controller: _infiniteScrollController,
            axisDirection: Axis.horizontal,
            loop: true,
            itemBuilder: (context, index, realIndex) {
              final dayOffset = index - 1000;
              final currentDate = DateTime.now().add(Duration(days: dayOffset));
              final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);
              final dayEvents = _events[dateKey] ?? [];
              final itemHeight = 120.0;
              final totalHeight =
                  24 * itemHeight; // (your current scale: 120px per hour)
              return SingleChildScrollView(
                child: SizedBox(
                  height: totalHeight,
                  child: Stack(
                    children: [
                      // 1. Vertical Lines
                      ...List.generate(47, (halfHour) {
                        final halfHeight = itemHeight * 0.5;
                        final double top =
                            halfHour * halfHeight; // hour to minute by 60
                        return Positioned(
                          top: top,
                          left: dayWidth - 1,
                          child: Container(
                            width: 1,
                            color: widget.style.borderColor,
                            height: halfHeight,
                          ),
                        );
                      }),
                      // 2. Hour lines & labels
                      ...List.generate(47, (halfHour) {
                        final halfHeight = itemHeight * 0.5;
                        final double top =
                            halfHour * halfHeight; // hour to minute by 60
                        final hour = (halfHour / 2).floor();
                        return Positioned(
                          top: top,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              // Time label
                              Opacity(
                                opacity: halfHour % 2 == 0 ? 1 : 0,
                                child: SizedBox(
                                  width: dayWidth,
                                  child: Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 4.0,
                                      ),
                                      child: Text(
                                        DateFormat(
                                          'h a',
                                        ).format(DateTime(2023, 1, 1, hour)),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Divider
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: widget.style.borderColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      // 3. Current Time
                      Positioned(
                        top: currentInMinute * itemHeight / 60,
                        left: dayWidth - 6,
                        right: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.style.currentTimeColor,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: widget.style.currentTimeColor,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                DateFormat('hh:mm a').format(DateTime.now()),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: widget.style.currentTimeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 4. All events as positioned widgets
                      ...dayEvents.mapIndex((index, event) {
                        final startMinutes =
                            event.startTime.hour * itemHeight +
                            event.startTime.minute * (itemHeight / 60);
                        final endMinutes =
                            event.endTime.hour * itemHeight +
                            event.endTime.minute * (itemHeight / 60);
                        final top = startMinutes.toDouble() + 8;
                        final height = (endMinutes - startMinutes).toDouble();
                        return Positioned(
                          top: top,
                          left: dayWidth + 8,
                          right: 8,
                          height: height,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: event.color.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: event.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        event.title,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${event.startTime.format(context)} - ${event.endTime.format(context)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CalendarEvent {
  final String title;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final Color color;

  CalendarEvent(this.title, this.startTime, this.endTime, this.color);
}
