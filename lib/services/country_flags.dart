// lib/services/country_flags.dart
//
// Bandera emoji a partir del código ISO-3 (el que usa la tabla countries).
// Autocontenido: mapa ISO3→ISO2 y conversión a "regional indicators".
// Si el código no está en el mapa, devuelve 🌍 (nunca rompe la UI).

String flagFromIso3(String iso3) {
  final iso2 = _iso3to2[iso3.toUpperCase()];
  if (iso2 == null || iso2.length != 2) return '🌍';
  final base = 0x1F1E6; // 🇦
  final a = base + (iso2.codeUnitAt(0) - 65);
  final b = base + (iso2.codeUnitAt(1) - 65);
  return String.fromCharCodes([a, b]);
}

const Map<String, String> _iso3to2 = {
  'AFG': 'AF', 'ALB': 'AL', 'DZA': 'DZ', 'AND': 'AD', 'AGO': 'AO',
  'ARG': 'AR', 'ARM': 'AM', 'AUS': 'AU', 'AUT': 'AT', 'AZE': 'AZ',
  'BHS': 'BS', 'BHR': 'BH', 'BGD': 'BD', 'BRB': 'BB', 'BLR': 'BY',
  'BEL': 'BE', 'BLZ': 'BZ', 'BEN': 'BJ', 'BTN': 'BT', 'BOL': 'BO',
  'BIH': 'BA', 'BWA': 'BW', 'BRA': 'BR', 'BRN': 'BN', 'BGR': 'BG',
  'BFA': 'BF', 'BDI': 'BI', 'CPV': 'CV', 'KHM': 'KH', 'CMR': 'CM',
  'CAN': 'CA', 'CAF': 'CF', 'TCD': 'TD', 'CHL': 'CL', 'CHN': 'CN',
  'COL': 'CO', 'COM': 'KM', 'COG': 'CG', 'COD': 'CD', 'CRI': 'CR',
  'CIV': 'CI', 'HRV': 'HR', 'CUB': 'CU', 'CYP': 'CY', 'CZE': 'CZ',
  'DNK': 'DK', 'DJI': 'DJ', 'DMA': 'DM', 'DOM': 'DO', 'ECU': 'EC',
  'EGY': 'EG', 'SLV': 'SV', 'GNQ': 'GQ', 'ERI': 'ER', 'EST': 'EE',
  'SWZ': 'SZ', 'ETH': 'ET', 'FJI': 'FJ', 'FIN': 'FI', 'FRA': 'FR',
  'GAB': 'GA', 'GMB': 'GM', 'GEO': 'GE', 'DEU': 'DE', 'GHA': 'GH',
  'GRC': 'GR', 'GRD': 'GD', 'GTM': 'GT', 'GIN': 'GN', 'GNB': 'GW',
  'GUY': 'GY', 'HTI': 'HT', 'HND': 'HN', 'HUN': 'HU', 'ISL': 'IS',
  'IND': 'IN', 'IDN': 'ID', 'IRN': 'IR', 'IRQ': 'IQ', 'IRL': 'IE',
  'ISR': 'IL', 'ITA': 'IT', 'JAM': 'JM', 'JPN': 'JP', 'JOR': 'JO',
  'KAZ': 'KZ', 'KEN': 'KE', 'KIR': 'KI', 'PRK': 'KP', 'KOR': 'KR',
  'KWT': 'KW', 'KGZ': 'KG', 'LAO': 'LA', 'LVA': 'LV', 'LBN': 'LB',
  'LSO': 'LS', 'LBR': 'LR', 'LBY': 'LY', 'LIE': 'LI', 'LTU': 'LT',
  'LUX': 'LU', 'MDG': 'MG', 'MWI': 'MW', 'MYS': 'MY', 'MDV': 'MV',
  'MLI': 'ML', 'MLT': 'MT', 'MHL': 'MH', 'MRT': 'MR', 'MUS': 'MU',
  'MEX': 'MX', 'FSM': 'FM', 'MDA': 'MD', 'MCO': 'MC', 'MNG': 'MN',
  'MNE': 'ME', 'MAR': 'MA', 'MOZ': 'MZ', 'MMR': 'MM', 'NAM': 'NA',
  'NRU': 'NR', 'NPL': 'NP', 'NLD': 'NL', 'NZL': 'NZ', 'NIC': 'NI',
  'NER': 'NE', 'NGA': 'NG', 'MKD': 'MK', 'NOR': 'NO', 'OMN': 'OM',
  'PAK': 'PK', 'PLW': 'PW', 'PSE': 'PS', 'PAN': 'PA', 'PNG': 'PG',
  'PRY': 'PY', 'PER': 'PE', 'PHL': 'PH', 'POL': 'PL', 'PRT': 'PT',
  'QAT': 'QA', 'ROU': 'RO', 'RUS': 'RU', 'RWA': 'RW', 'KNA': 'KN',
  'LCA': 'LC', 'VCT': 'VC', 'WSM': 'WS', 'SMR': 'SM', 'STP': 'ST',
  'SAU': 'SA', 'SEN': 'SN', 'SRB': 'RS', 'SYC': 'SC', 'SLE': 'SL',
  'SGP': 'SG', 'SVK': 'SK', 'SVN': 'SI', 'SLB': 'SB', 'SOM': 'SO',
  'ZAF': 'ZA', 'SSD': 'SS', 'ESP': 'ES', 'LKA': 'LK', 'SDN': 'SD',
  'SUR': 'SR', 'SWE': 'SE', 'CHE': 'CH', 'SYR': 'SY', 'TWN': 'TW',
  'TJK': 'TJ', 'TZA': 'TZ', 'THA': 'TH', 'TLS': 'TL', 'TGO': 'TG',
  'TON': 'TO', 'TTO': 'TT', 'TUN': 'TN', 'TUR': 'TR', 'TKM': 'TM',
  'TUV': 'TV', 'UGA': 'UG', 'UKR': 'UA', 'ARE': 'AE', 'GBR': 'GB',
  'USA': 'US', 'URY': 'UY', 'UZB': 'UZ', 'VUT': 'VU', 'VAT': 'VA',
  'VEN': 'VE', 'VNM': 'VN', 'YEM': 'YE', 'ZMB': 'ZM', 'ZWE': 'ZW',
  'XKX': 'XK', 'HKG': 'HK', 'MAC': 'MO', 'PRI': 'PR',
};
