import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:assets_audio_player/assets_audio_player.dart' as MyAssetAudioPlayer;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:marquee_text/marquee_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:social_share/social_share.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );
  print('User granted permission: ${settings.authorizationStatus}');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: (5)),
      vsync: this,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Lottie.asset(
        'assets/lf_animation.json',
        controller: _controller,
        height: MediaQuery.of(context).size.height * 1,
        animate: true,
        onLoaded: (composition) {
          _controller
            ..duration = composition.duration
            ..forward().whenComplete(() => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (context) => MyHomePage(title: 'HHLS Radio'))));
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const String API_URL = "https://radio.hhls.fr/api";
  late Timer _timer;

  var _assetsAudioPlayer = MyAssetAudioPlayer.AssetsAudioPlayer();
  ScreenshotController screenshotController = ScreenshotController();

  var listenUrl = "";

  var nowPlayingText = "";
  var _clientIsScreening = false;
  var nowPlayingTitle = "";
  var nowPlayingArtist = "";
  var nowPlayingCover = "";

  var historySongs = [];

  @override
  void dispose() {
    _assetsAudioPlayer.dispose();
    _timer.cancel();

    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    MyAssetAudioPlayer.AssetsAudioPlayer.setupNotificationsOpenAction((notification) {
      return true;
    });

    initStreaming();
  }

  Future<void> getListenUrl() async {
    var response = await http.get(Uri.parse(API_URL + '/nowplaying'));
    var data = json.decode(utf8.decode(response.bodyBytes));

    listenUrl = data[0]['station']['listen_url'];
  }

  Future<void> refreshMetadatas({bool forced = false}) async {
    var response = await http.get(Uri.parse(API_URL + '/nowplaying'));
    var data = json.decode(utf8.decode(response.bodyBytes));

    var oldCover = nowPlayingCover;

    nowPlayingText = data[0]['now_playing']['song']['text'];
    nowPlayingTitle = data[0]['now_playing']['song']['title'];
    nowPlayingArtist = data[0]['now_playing']['song']['artist'];
    nowPlayingCover = data[0]['now_playing']['song']['art'];

    var allPastSongs = data[0]['song_history'];

    historySongs = [];
    for (var pastSong in allPastSongs) {
      historySongs.add(pastSong["song"]["text"]);
    }

    if (oldCover != nowPlayingCover) {
      print('updated new Cover');
      _assetsAudioPlayer.updateCurrentAudioNotification(
          metas: MyAssetAudioPlayer.Metas(
              title: nowPlayingTitle,
              artist: nowPlayingArtist,
              image: MyAssetAudioPlayer.MetasImage.network(nowPlayingCover)));
    }

    if (forced) {
      print('forced update new Cover');

      _assetsAudioPlayer.updateCurrentAudioNotification(
          metas: MyAssetAudioPlayer.Metas(
              title: nowPlayingTitle,
              artist: nowPlayingArtist,
              image: MyAssetAudioPlayer.MetasImage.network(nowPlayingCover)));
    }
    setState(() {});
  }

  Future<void> initStreaming() async {
    // Retrieve STREAM URL
    // await getListenUrl();
    // Refresh Metadata
    await refreshMetadatas();

    // Create AudioPlayer
    await _assetsAudioPlayer.open(MyAssetAudioPlayer.Audio.network("https://radio.hhls.fr/radio/8000/mobile.mp3"),
        showNotification: true,
        loopMode: MyAssetAudioPlayer.LoopMode.single,
        notificationSettings: MyAssetAudioPlayer.NotificationSettings(
            nextEnabled: false, prevEnabled: false, playPauseEnabled: true, customPlayPauseAction: myCustomPlayPause),
        autoStart: false,
        audioFocusStrategy: MyAssetAudioPlayer.AudioFocusStrategy.request(
            resumeAfterInterruption: true, resumeOthersPlayersAfterDone: false),
        respectSilentMode: false);
  }

  void myCustomPlayPause(MyAssetAudioPlayer.AssetsAudioPlayer player) async {
    if (!player.isPlaying.value) {
      // await player.stop();
      togglePlay();
    } else {
      togglePause();
    }
  }

  void startAutoRefreshMetadata() {
    // Start timer auto refresh metadatas
    refreshMetadatas(forced: true);
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      refreshMetadatas();
    });
  }

  void stopAutoRefreshMetadata() {
    // Stop timer auto refresh metadatas
    _timer.cancel();
  }

  void togglePlay() async {
    await _assetsAudioPlayer.stop();
    await _assetsAudioPlayer.play();
    startAutoRefreshMetadata();
    setState(() {});
  }

  void togglePause() async {
    await _assetsAudioPlayer.pause();
    stopAutoRefreshMetadata();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: SafeArea(
          child: Screenshot(
            controller: screenshotController,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 55),
                child: Container(
                  color: Colors.black,
                  child: Column(
                    children: <Widget>[
                      Column(
                        children: [
                          SizedBox(height: 35),
                          Image(image: AssetImage('images/logo.png'), height: 50),
                          SizedBox(height: 35),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            MyBlinkingButton(),
                            SizedBox(width: 6),
                            Text(
                              'Live Now',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ]),
                          SizedBox(height: 12),
                          _assetsAudioPlayer.builderIsBuffering(builder: (context, isBuffering) {
                            return Container(
                              child: _assetsAudioPlayer.builderIsPlaying(builder: (context2, isPlaying) {
                                return InkWell(
                                    onTap: isBuffering
                                        ? null
                                        : () {
                                            isPlaying ? togglePause() : togglePlay();
                                          },
                                    child: Container(
                                        height: MediaQuery.of(context).size.height / 3,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                            image: DecorationImage(
                                                image: NetworkImage(nowPlayingCover), fit: BoxFit.contain)),
                                        child: isBuffering
                                            ? Icon(Icons.arrow_circle_down, size: 80, color: Colors.white)
                                            : (isPlaying
                                                ? Icon(Icons.pause, size: 80, color: Colors.white)
                                                : Icon(Icons.play_arrow, size: 80, color: Colors.white))));
                              }),
                            );
                          }),
                          SizedBox(height: 10),
                          Container(
                            child: _clientIsScreening
                                ? Text(nowPlayingText,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))
                                : MarqueeText(
                                    text: TextSpan(
                                      text: nowPlayingText, // Assuming nowPlayingText is a String
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    alwaysScroll: false,
                                    speed: 8),
                          ),
                          Container(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 20),
                                Text(
                                  "TRACK ID",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "PREVIOUSLY",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w400,
                                      fontSize: 14,
                                      letterSpacing: 1.5),
                                ),
                                SizedBox(height: 20),
                                for (var song in historySongs)
                                  Column(children: [
                                    Text(
                                      song,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.normal,
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(height: 5)
                                  ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Spacer(flex: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                  onTap: () async {
                                    if (await canLaunch('fb://page/174587659372990')) {
                                      await launch('fb://page/174587659372990');
                                    } else {
                                      await launch('https://www.facebook.com/hhlsmusic', enableJavaScript: true);
                                    }
                                  },
                                  child: Icon(Icons.facebook, size: 24, color: Colors.white)),
                              SizedBox(width: 20),
                              InkWell(
                                onTap: () async {
                                  if (await canLaunch('instagram://user?username=hhlsmusic')) {
                                    await launch('instagram://user?username=hhlsmusic');
                                  } else {
                                    await launch('https://www.instagram.com/hhlsmusic', enableJavaScript: true);
                                  }
                                },
                                child: SvgPicture.asset(
                                  "images/svg/instagram.svg",
                                  color: Colors.white,
                                  height: 22,
                                  width: 22,
                                ),
                              ),
                              SizedBox(width: 20),
                              InkWell(
                                onTap: () async {
                                  if (await canLaunch('twitter://user?screen_name=hhlsmusic')) {
                                    await launch('twitter://user?screen_name=hhlsmusic');
                                  } else {
                                    await launch('https://twitter.com/hhlsmusic', enableJavaScript: true);
                                  }
                                },
                                child: SvgPicture.asset(
                                  "images/svg/twitter.svg",
                                  color: Colors.white,
                                  height: 22,
                                  width: 22,
                                ),
                              ),
                              SizedBox(width: 20),
                              InkWell(
                                onTap: () async {
                                  if (await canLaunch('https://hhls.fr')) {
                                    await launch('https://hhls.fr', enableJavaScript: true);
                                  }
                                },
                                child: SvgPicture.asset(
                                  "images/svg/fi-br-globe.svg",
                                  color: Colors.white,
                                  height: 22,
                                  width: 22,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () async {
                              _clientIsScreening = true;
                              setState(() {});
                              // set le titre en dur removed textSpeed
                              screenshotController.capture(delay: Duration(milliseconds: 10)).then((image) async {
                                _clientIsScreening = false;
                                setState(() {});
                                Directory tempDir = await getTemporaryDirectory();
                                String filePath = '${tempDir.path}/my_image.jpg';
                                await File(filePath).writeAsBytes(image!);
                                SocialShare.shareInstagramStory(
                                  backgroundTopColor: "#000000",
                                  backgroundBottomColor: "#000000",
                                  attributionURL: "https://hhls.fr",
                                  appId: '',
                                  imagePath: filePath,
                                );
                              });
                            },
                            child: SvgPicture.asset(
                              "images/svg/fi-br-upload.svg",
                              color: Colors.white,
                              height: 22,
                              width: 22,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20)
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyBlinkingButton extends StatefulWidget {
  @override
  _MyBlinkingButtonState createState() => _MyBlinkingButtonState();
}

class _MyBlinkingButtonState extends State<MyBlinkingButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    _animationController = new AnimationController(vsync: this, duration: Duration(seconds: 1));
    _animationController.repeat(reverse: true);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animationController, child: Icon(Icons.circle, size: 8, color: Colors.red));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
