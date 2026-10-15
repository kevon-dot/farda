import 'package:farda/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumer routes retain the integrated app and v2 preview paths', () {
    expect(CustomRoutePaths.dashboard, '/dashboard');
    expect(CustomRoutePaths.consumer, '/consumer');
    expect(CustomRoutePaths.consumerDemo, '/consumer/demo');
    expect(CustomRoutePaths.consumerV2, '/consumer/v2');
    expect(CustomRoutePaths.consumerV2Today, '/consumer/v2/today');
    expect(CustomRoutePaths.consumerV2Calendar, '/consumer/v2/calendar');
    expect(CustomRoutePaths.consumerV2Refills, '/consumer/v2/refills');
    expect(CustomRoutePaths.consumerV2You, '/consumer/v2/you');
    expect(
      CustomRoutePaths.consumerV2TabPath(0),
      CustomRoutePaths.consumerV2Today,
    );
    expect(
      CustomRoutePaths.consumerV2TabPath(3),
      CustomRoutePaths.consumerV2You,
    );
    expect(CustomRoutePaths.home, '/home');
    expect(CustomRoutePaths.plan, '/plan');
    expect(CustomRoutePaths.calendar, '/calendar');
    expect(CustomRoutePaths.more, '/more');
  });
}
