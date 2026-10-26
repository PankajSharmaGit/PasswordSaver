/// Supported countries for onboarding (ISO 3166-1 alpha-2).
class CountryOption {
  const CountryOption({required this.code, required this.name});

  final String code;
  final String name;

  String get flagEmoji {
    if (code.length != 2) return '';
    final upper = code.toUpperCase();
    return String.fromCharCodes([
      upper.codeUnitAt(0) + 0x1F1A5,
      upper.codeUnitAt(1) + 0x1F1A5,
    ]);
  }
}

class SupportedCountries {
  SupportedCountries._();

  static const List<CountryOption> all = [
    CountryOption(code: 'IN', name: 'India'),
    CountryOption(code: 'US', name: 'United States'),
    CountryOption(code: 'GB', name: 'United Kingdom'),
    CountryOption(code: 'CA', name: 'Canada'),
    CountryOption(code: 'AU', name: 'Australia'),
    CountryOption(code: 'AE', name: 'United Arab Emirates'),
    CountryOption(code: 'SA', name: 'Saudi Arabia'),
    CountryOption(code: 'SG', name: 'Singapore'),
    CountryOption(code: 'MY', name: 'Malaysia'),
    CountryOption(code: 'DE', name: 'Germany'),
    CountryOption(code: 'FR', name: 'France'),
    CountryOption(code: 'IT', name: 'Italy'),
    CountryOption(code: 'ES', name: 'Spain'),
    CountryOption(code: 'NL', name: 'Netherlands'),
    CountryOption(code: 'BE', name: 'Belgium'),
    CountryOption(code: 'CH', name: 'Switzerland'),
    CountryOption(code: 'SE', name: 'Sweden'),
    CountryOption(code: 'NO', name: 'Norway'),
    CountryOption(code: 'DK', name: 'Denmark'),
    CountryOption(code: 'FI', name: 'Finland'),
    CountryOption(code: 'IE', name: 'Ireland'),
    CountryOption(code: 'PT', name: 'Portugal'),
    CountryOption(code: 'PL', name: 'Poland'),
    CountryOption(code: 'AT', name: 'Austria'),
    CountryOption(code: 'CZ', name: 'Czech Republic'),
    CountryOption(code: 'GR', name: 'Greece'),
    CountryOption(code: 'RO', name: 'Romania'),
    CountryOption(code: 'HU', name: 'Hungary'),
    CountryOption(code: 'RU', name: 'Russia'),
    CountryOption(code: 'UA', name: 'Ukraine'),
    CountryOption(code: 'TR', name: 'Turkey'),
    CountryOption(code: 'IL', name: 'Israel'),
    CountryOption(code: 'EG', name: 'Egypt'),
    CountryOption(code: 'ZA', name: 'South Africa'),
    CountryOption(code: 'NG', name: 'Nigeria'),
    CountryOption(code: 'KE', name: 'Kenya'),
    CountryOption(code: 'PK', name: 'Pakistan'),
    CountryOption(code: 'BD', name: 'Bangladesh'),
    CountryOption(code: 'LK', name: 'Sri Lanka'),
    CountryOption(code: 'NP', name: 'Nepal'),
    CountryOption(code: 'AF', name: 'Afghanistan'),
    CountryOption(code: 'ID', name: 'Indonesia'),
    CountryOption(code: 'PH', name: 'Philippines'),
    CountryOption(code: 'TH', name: 'Thailand'),
    CountryOption(code: 'VN', name: 'Vietnam'),
    CountryOption(code: 'JP', name: 'Japan'),
    CountryOption(code: 'KR', name: 'South Korea'),
    CountryOption(code: 'CN', name: 'China'),
    CountryOption(code: 'HK', name: 'Hong Kong'),
    CountryOption(code: 'TW', name: 'Taiwan'),
    CountryOption(code: 'NZ', name: 'New Zealand'),
    CountryOption(code: 'MX', name: 'Mexico'),
    CountryOption(code: 'BR', name: 'Brazil'),
    CountryOption(code: 'AR', name: 'Argentina'),
    CountryOption(code: 'CL', name: 'Chile'),
    CountryOption(code: 'CO', name: 'Colombia'),
    CountryOption(code: 'PE', name: 'Peru'),
    CountryOption(code: 'QA', name: 'Qatar'),
    CountryOption(code: 'KW', name: 'Kuwait'),
    CountryOption(code: 'OM', name: 'Oman'),
    CountryOption(code: 'BH', name: 'Bahrain'),
    CountryOption(code: 'JO', name: 'Jordan'),
    CountryOption(code: 'LB', name: 'Lebanon'),
    CountryOption(code: 'IQ', name: 'Iraq'),
    CountryOption(code: 'IR', name: 'Iran'),
    CountryOption(code: 'MA', name: 'Morocco'),
    CountryOption(code: 'DZ', name: 'Algeria'),
    CountryOption(code: 'TN', name: 'Tunisia'),
    CountryOption(code: 'GH', name: 'Ghana'),
    CountryOption(code: 'ET', name: 'Ethiopia'),
    CountryOption(code: 'MU', name: 'Mauritius'),
    CountryOption(code: 'XX', name: 'Other'),
  ];

  static CountryOption? byCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final c in all) {
      if (c.code == normalized) return c;
    }
    return null;
  }
}
