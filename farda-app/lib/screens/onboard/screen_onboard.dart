
import 'package:farda/components/_components.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/login/screen_login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenOnboard extends StatefulWidget {
  const ScreenOnboard({super.key});

  @override
  State<ScreenOnboard> createState() => _ScreenOnboardState();
}

class _ScreenOnboardState extends State<ScreenOnboard> {
    Future<void> getInitialRoute() async {
    final prefs = await SharedPreferences.getInstance();
    String? isLoggedIn = prefs.getString('id');

    if (isLoggedIn != null && isLoggedIn.isNotEmpty) {
       context.go(CustomRoutePaths.dashboard);
    } else {
      context.go( CustomRoutePaths.onboard);
    }
  }
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getInitialRoute();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/onboard-bg.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 65,
                child: Image.asset(
                  "assets/images/onboard-hero.png",
                  fit: BoxFit.contain,
                ),
              ),
              Expanded(
                flex: 35,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset("assets/images/farda.png", height: 0.045.sh),
                    8.verticalSpace,
                    TextMedium(
                      text: "Consume, Right",
                      style: TextStyle(fontSize: 17.sp),
                    ),
                    Spacer(),
                    _shaderText(text: "Start Here"),
                    Spacer(),
                    ButtonPrimary(
                      text: "Get Started",
                      onClick: () {
                        // context.go("/login");
                        // context.(RouteLogin());
                        Navigator.push(context, MaterialPageRoute(builder: (_)=> ScreenLogin()));
                      },
                    ),
                    12.verticalSpace,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shaderText({required String text}) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          colors: [Color(0xFF535862), Color(0xFFADAEB1), Color(0xFF717680)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds);
      },
      child: Text(
        text,
        style: TextStyle(
          fontSize: 32.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
