import 'package:farda/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumer routes retain dashboard and legacy entry points', () {
    expect(CustomRoutePaths.dashboard, '/dashboard');
    expect(CustomRoutePaths.today, '/dashboard/today');
    expect(CustomRoutePaths.calendar, '/dashboard/calendar');
    expect(CustomRoutePaths.refills, '/dashboard/refills');
    expect(CustomRoutePaths.you, '/dashboard/you');
    expect(CustomRoutePaths.home, CustomRoutePaths.today);
    expect(CustomRoutePaths.plan, CustomRoutePaths.refills);
    expect(CustomRoutePaths.more, CustomRoutePaths.you);
    expect(CustomRoutePaths.consumerTabPath(0), CustomRoutePaths.today);
    expect(CustomRoutePaths.consumerTabPath(3), CustomRoutePaths.you);
  });
}
