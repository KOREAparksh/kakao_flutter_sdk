import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:kakao_flutter_sdk_common/src/constants.dart';
import 'package:kakao_flutter_sdk_common/src/kakao_sdk.dart';
import 'package:kakao_flutter_sdk_common/src/util.dart';
import 'package:kakao_flutter_sdk_common/src/web/common.dart';
import 'package:kakao_flutter_sdk_common/src/web/login.dart';
import 'package:kakao_flutter_sdk_common/src/web/navi.dart';
import 'package:kakao_flutter_sdk_common/src/web/picker.dart';
import 'package:kakao_flutter_sdk_common/src/web/talk.dart';
import 'package:kakao_flutter_sdk_common/src/web/ua_parser.dart';
import 'package:kakao_flutter_sdk_common/src/web/user.dart';
import 'package:kakao_flutter_sdk_common/src/web/utility.dart';

class KakaoFlutterSdkPlugin {
  final _uaParser = UaParser();

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
        CommonConstants.methodChannel, const StandardMethodCodec(), registrar);

    final KakaoFlutterSdkPlugin instance = KakaoFlutterSdkPlugin();
    channel.setMethodCallHandler(instance.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    String userAgent = html.window.navigator.userAgent;
    Browser currentBrowser = _uaParser.detectBrowser(userAgent);

    switch (call.method) {
      case "appVer":
        return await Utility.getAppVersion();
      case "packageName":
        return await Utility.getPackageName();
      case "launchBrowserTab":
        Map<dynamic, dynamic> args = call.arguments;
        String uri = args["url"];
        bool popupLogin = args[CommonConstants.isPopup];
        final fullUri = Uri.parse(uri);
        Map<String, dynamic> queryParameters =
            Map.from(fullUri.queryParameters);

        if (!popupLogin) {
          queryParameters[CommonConstants.redirectUri] =
              args[CommonConstants.redirectUri];
          final finalUri = fullUri.replace(queryParameters: queryParameters);
          html.window.location.href = finalUri.toString();
          return;
        }

        queryParameters[CommonConstants.redirectUri] =
            html.window.location.origin;
        final finalUri = fullUri.replace(queryParameters: queryParameters);
        final popupWindow =
            html.window.open(finalUri.toString(), "KakaoAccountLogin");

        final msg = await html.window.onMessage.firstWhere((evt) {
          if (evt.data.runtimeType != String) return false;

          return evt.origin ==
              Uri.parse(queryParameters[CommonConstants.redirectUri]).origin;
        });

        popupWindow.close();

        return msg.data;
      case "retrieveAuthCode":
        _retrieveAuthCode();
        break;
      case "getOrigin":
        return html.window.location.origin;
      case "getKaHeader":
        return _getKaHeader();
      case 'isKakaoTalkSharingAvailable':
      case 'isKakaoNaviInstalled':
      case "isKakaoTalkInstalled":
        if (isMobileDevice()) {
          return true;
        }
        return false;
      case "platformId":
        final origin = Uri.parse(html.window.location.origin)
            .authority
            .split('')
            .map((e) => e.codeUnits[0])
            .toList();
        int end = origin.length >= 10 ? 10 : origin.length;
        return Uint8List.fromList(origin.sublist(0, end));
      case "platformRedirectUri":
        if (isAndroid()) {
          return "${CommonConstants.scheme}://${KakaoSdk.hosts.kapi}${CommonConstants.androidWebRedirectUri}";
        } else if (isiOS()) {
          return CommonConstants.iosWebRedirectUri;
        }
        // Returns meaningless values unless Android and iOS.
        return html.window.origin;
      case 'redirectForEasyLogin':
        final String redirectUri = call.arguments['redirect_uri'];
        final String code = call.arguments['code'];
        final String state = call.arguments['state'];
        html.window.location.href =
            '$redirectUri?code=${Uri.encodeComponent(code)}&state=${Uri.encodeComponent(state)}';
        return;
      case "authorizeWithTalk":
        if (!isMobileDevice()) {
          throw PlatformException(
              code: 'NotImplemented',
              message:
                  'KakaoTalk easy login is only available on Android or iOS devices.');
        }

        var arguments = call.arguments;
        final kaHeader = await KakaoSdk.kaHeader;

        if (isAndroid()) {
          String intent =
              androidLoginIntent(kaHeader, userAgent, Map.castFrom(arguments));
          html.window.location.href = intent;
        } else if (isiOS()) {
          final universalLink =
              iosLoginUniversalLink(kaHeader, Map.castFrom(arguments));

          if (currentBrowser == Browser.safari) {
            html.window.open(universalLink, "_blank");
          } else {
            html.window.location.href = universalLink;
          }
        }
        break;
      case 'launchKakaoTalk':
        String uri = call.arguments['uri'];

        if (!isMobileDevice()) {
          throw PlatformException(
            code: 'NotImplemented',
            message:
                'KakaoTalk can only be launched on Android or iOS devices.',
          );
        }

        if (isAndroid()) {
          final intent = _getAndroidShareIntent(userAgent, uri);
          html.window.location.href = intent;
          return true;
        } else if (isiOS()) {
          html.window.location.href = uri;
          return true;
        }
        break;
      case 'selectShippingAddresses':
        Browser currentBrowser = _uaParser.detectBrowser(userAgent);
        if ({Browser.facebook, Browser.instagram}.contains(currentBrowser)) {
          return jsonEncode({
            'error_code': 'KAE007',
            'error_msg': 'unsupported environment.',
          });
        }

        final String appKey = KakaoSdk.appKey;
        final String ka = await KakaoSdk.kaHeader;
        final String transId = call.arguments['trans_id'];
        final String? mobileView = call.arguments['mobile_view'];
        final String? enableBackButton = call.arguments['enable_back_button'];
        final String agt = call.arguments['agt'];

        final continueUrlParams = {
          'app_key': appKey,
          'ka': ka,
          'trans_id': transId,
          'mobile_view': mobileView,
          'enable_back_button': enableBackButton,
        };
        continueUrlParams.removeWhere((k, v) => v == null);

        final continueUrl = createSelectShippingAddressesUrl(continueUrlParams);
        final kpidtUrl = createKpidtUrl({
          'app_key': KakaoSdk.appKey,
          'agt': agt,
          'continue': continueUrl,
        });
        return handleAppsApi(transId, kpidtUrl, 'select_shipping_addresses');
      case 'followChannel':
        Browser currentBrowser = _uaParser.detectBrowser(userAgent);
        if ({Browser.facebook, Browser.instagram}.contains(currentBrowser)) {
          return jsonEncode({
            'error_code': 'KAE007',
            'error_msg': 'unsupported environment.',
          });
        }

        final String channelPublicId = call.arguments['channel_public_id'];
        final String transId = call.arguments['trans_id'];
        final String? agt = call.arguments['agt'];

        final params = {
          'ka': await KakaoSdk.kaHeader,
          'app_key': KakaoSdk.appKey,
          'channel_public_id': channelPublicId,
          'trans_id': transId,
          'agt': agt,
        };
        params.removeWhere((k, v) => v == null);
        final requestUrl = createFollowChannelUrl(params);
        return handleAppsApi(transId, requestUrl, 'follow_channel');
      case "addChannel":
        var scheme = call.arguments['channel_scheme'];
        var channelPublicId = call.arguments['channel_public_id'];

        if (!isMobileDevice()) {
          var url = await webChannelUrl('$channelPublicId/friend');
          windowOpen(url, 'channel_add_social_plugin');
          return;
        }

        final path = 'home/$channelPublicId/add';
        if (isAndroid()) {
          html.window.location.href =
              androidChannelIntent(scheme, channelPublicId, path);
        } else if (isiOS()) {
          html.window.location.href =
              iosChannelScheme(scheme, channelPublicId, path);
        }
        break;
      case "channelChat":
        var scheme = call.arguments['channel_scheme'];
        var channelPublicId = call.arguments['channel_public_id'];

        if (!isMobileDevice()) {
          var url = await webChannelUrl('$channelPublicId/chat');
          windowOpen(url, 'channel_chat_social_plugin');
          return;
        }

        final path = 'talk/chat/$channelPublicId';
        final extra = 'extra={"referer": "${html.window.location.href}"}';
        if (isAndroid()) {
          html.window.location.href = androidChannelIntent(
              scheme, channelPublicId, path,
              queryParameters: extra);
        } else if (isiOS()) {
          html.window.location.href = iosChannelScheme(
              scheme, channelPublicId, path,
              queryParameters: extra);
        }
        break;
      case "navigate":
      case "shareDestination":
        String scheme = call.arguments['navi_scheme'];
        String queries =
            'apiver=1.0&appkey=${KakaoSdk.appKey}&param=${Uri.encodeComponent(call.arguments['navi_params'])}&extras=${Uri.encodeComponent(call.arguments['extras'])}';

        if (isAndroid()) {
          html.window.location.href = androidNaviIntent(scheme, queries);
          return true;
        } else if (isiOS()) {
          bindPageHideEvent(deferredFallback(
              '${KakaoSdk.platforms.web.kakaoNaviInstallPage}?$queries',
              (storeUrl) {
            html.window.top?.location.href = storeUrl;
          }));
          html.window.location.href = '$scheme?$queries';
          return true;
        }
        return false;
      case "requestWebPicker":
        final String pickerType = call.arguments['picker_type'];
        final String transId = call.arguments['trans_id'];
        final String accessToken = call.arguments['access_token'];
        final Map pickerParams = call.arguments['picker_params'];

        final url = 'https://${KakaoSdk.hosts.picker}';

        final iframe =
            createHiddenIframe(transId, '$url/proxy?transId=$transId');
        html.document.body?.append(iframe);

        final params = await createPickerParams(
          accessToken,
          transId,
          Map.castFrom(pickerParams),
        );

        // redirect picker
        if (params.containsKey('returnUrl')) {
          submitForm('$url/select/$pickerType', params);
          return;
        }

        // popup picker
        final completer = Completer<String>();
        final callback = addMessageEventListener(
            url, completer, (response) => response.containsKey('code'));

        final popup = windowOpen(
          '$url/select/$pickerType',
          'friend_picker',
          features:
              'location=no,resizable=no,status=no,scrollbars=no,width=460,height=608',
        );

        submitForm(
          '$url/select/$pickerType',
          params,
          popupName: 'friend_picker',
        );

        popup.afterClosed(() {
          html.window.removeEventListener('message', callback);
          html.document.getElementById(transId)?.remove();
        });

        return completer.future;
      default:
        throw PlatformException(
            code: "NotImplemented",
            details:
                "KakaoFlutterSdk for web doesn't implement the method ${call.method}");
    }
  }

  void _retrieveAuthCode() {
    final uri = Uri.parse(html.window.location.search!);
    final params = uri.queryParameters;
    if (params.containsKey("code") || params.containsKey("error")) {
      html.window.opener?.postMessage(html.window.location.href, "*");
      html.window.close();
    }
  }

  String _getKaHeader() {
    return "os/javascript origin/${html.window.location.origin}";
  }

  String _getAndroidShareIntent(String userAgent, String uri) {
    String intentScheme;
    String talkSharingScheme = KakaoSdk.platforms.android.talkSharingScheme;
    Browser currentBrowser = _uaParser.detectBrowser(userAgent);
    if (currentBrowser == Browser.facebook ||
        currentBrowser == Browser.instagram) {
      intentScheme =
          'intent://send?${uri.substring('$talkSharingScheme://send?'.length, uri.length)}#Intent;scheme=$talkSharingScheme';
    } else {
      uri = uri.replaceFirst(
          KakaoSdk.platforms.web.talkSharingScheme, talkSharingScheme);
      intentScheme = 'intent:$uri#Intent';
    }

    final intent = [
      intentScheme,
      'launchFlags=0x14008000',
      'package=${KakaoSdk.platforms.web.talkPackage}',
      'end;'
    ].join(';');
    return intent;
  }
}
