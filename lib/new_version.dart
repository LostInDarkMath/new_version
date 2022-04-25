library new_version;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';


/// The different design options.
enum Design {
  android,
  ios,
  useOsStyle,
}

/// Information about the app's current version, and the most recent version
/// available in the Apple App Store or Google Play Store.
class VersionStatus {
  /// The current version of the app.
  final String localVersion;

  /// The most recent version of the app in the store.
  final String storeVersion;

  /// A link to the app store page where the app can be updated.
  final String appStoreLink;

  /// The release notes for the store version of the app.
  final String? releaseNotes;

  /// Returns `true` if the store version of the application is greater than the local version.
  bool get canUpdate {
    final local = localVersion.split('.').map(int.parse).toList();
    final store = storeVersion.split('.').map(int.parse).toList();

    // Each consecutive field in the version notation is less significant than the previous one,
    // therefore only one comparison needs to yield `true` for it to be determined that the store
    // version is greater than the local version.
    for (var i = 0; i < store.length; i++) {
      // The store version field is newer than the local version.
      if (store[i] > local[i]) {
        return true;
      }

      // The local version field is newer than the store version.
      if (local[i] > store[i]) {
        return false;
      }
    }

    // The local and store versions are the same.
    return false;
  }

  VersionStatus._({
    required this.localVersion,
    required this.storeVersion,
    required this.appStoreLink,
    this.releaseNotes,
  });
}

class NewVersion {
  /// An optional value that can override the default packageName when
  /// attempting to reach the Apple App Store. This is useful if your app has
  /// a different package name in the App Store.
  final String? iOSId;

  /// An optional value that can override the default packageName when
  /// attempting to reach the Google Play Store. This is useful if your app has
  /// a different package name in the Play Store.
  final String? androidId;

  /// Only affects iOS App Store lookup: The two-letter country code for the store you want to search.
  /// Provide a value here if your app is only available outside the US.
  /// For example: US. The default is US.
  /// See http://en.wikipedia.org/wiki/ ISO_3166-1_alpha-2 for a list of ISO Country Codes.
  final String? iOSAppStoreCountry;

  NewVersion({
    this.androidId,
    this.iOSId,
    this.iOSAppStoreCountry,
  });

  /// This checks the version status, then displays a platform-specific alert
  /// with buttons to dismiss the update alert, or go to the app store.
  Future<void> showAlertIfNecessary({required BuildContext context}) async {
    final VersionStatus? versionStatus = await getVersionStatus();

    if (versionStatus != null && versionStatus.canUpdate) {
      await showUpdateDialog(context: context, versionStatus: versionStatus);
    }
  }

  /// This checks the version status and returns the information. This is useful
  /// if you want to display a custom alert, or use the information in a different
  /// way.
  Future<VersionStatus?> getVersionStatus() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isIOS) {
      return _getiOSStoreVersion(packageInfo);
    } else if (Platform.isAndroid) {
      return _getAndroidStoreVersion(packageInfo);
    } else {
      debugPrint('The target platform "${Platform.operatingSystem}" is not yet supported by this package.');
      return null;
    }
  }

  /// iOS info is fetched by using the iTunes lookup API, which returns a
  /// JSON document.
  Future<VersionStatus?> _getiOSStoreVersion(PackageInfo packageInfo) async {
    debugPrint(packageInfo.toString());
    final id = iOSId ?? packageInfo.packageName;
    final parameters = {'bundleId': id};

    if(iOSAppStoreCountry != null) {
      parameters.addAll({'country': iOSAppStoreCountry!});
    }

    var uri = Uri.https('itunes.apple.com', '/lookup', parameters);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      debugPrint('Failed to query iOS App Store');
      return null;
    }

    final jsonObj = json.decode(response.body) as Map<String, dynamic>;
    final results = jsonObj['results'] as List<dynamic>;

    if (results.isEmpty) {
      debugPrint('Can\'t find an app in the App Store with the id: $id');
      return null;
    }

    final first = results.first as Map<String, dynamic>;
    return VersionStatus._(
      localVersion: packageInfo.version,
      storeVersion: first['version'] as String,
      appStoreLink: first['trackViewUrl'] as String,
      releaseNotes: first['releaseNotes'] as String,
    );
  }

  /// Android info is fetched by parsing the html of the app store page.
  Future<VersionStatus?> _getAndroidStoreVersion(PackageInfo packageInfo) async {
    final id = androidId ?? packageInfo.packageName;
    final parameters = {'id': id};
    final uri = Uri.https('play.google.com', '/store/apps/details', parameters);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      debugPrint('Can\'t find an app in the Play Store with the id: $id');
      return null;
    }

    final document = parse(response.body);

    final additionalInfoElements = document.getElementsByClassName('hAyfc');
    final versionElement = additionalInfoElements.firstWhere(
      (elm) => elm.querySelector('.BgcNfc')!.text == 'Current Version',
    );
    final storeVersion = versionElement.querySelector('.htlgb')!.text;

    final sectionElements = document.getElementsByClassName('W4P4ne');
    final releaseNotesElement = sectionElements.firstWhereOrNull(
      (elm) => elm.querySelector('.wSaTQd')!.text == 'What\'s New',
    );
    final releaseNotes = releaseNotesElement
        ?.querySelector('.PHBdkd')
        ?.querySelector('.DWPxHb')
        ?.text;

    return VersionStatus._(
      localVersion: packageInfo.version,
      storeVersion: storeVersion,
      appStoreLink: uri.toString(),
      releaseNotes: releaseNotes,
    );
  }

  /// Shows the user a platform-specific alert about the app update. The user
  /// can dismiss the alert or proceed to the app store.
  ///
  /// To change the appearance and behavior of the update dialog, you can
  /// optionally provide [dialogTitle], [dialogText], [updateButtonText],
  /// [dismissButtonText], and [dismissAction] parameters.
  /// The [updateButtonStyle] and the [dismissButtonStyle] parameters are only used on Android.
  Future<void> showUpdateDialog({
    required BuildContext context,
    required VersionStatus versionStatus,
    Widget dialogTitle = const Text('Update Available'),
    Widget? dialogText,
    Widget updateButtonText = const Text('Update now'),
    bool allowDismissal = true,
    Widget dismissButtonText = const Text('Maybe Later'),
    VoidCallback? dismissAction,
    ButtonStyle? updateButtonStyle,
    ButtonStyle? dismissButtonStyle,
    Design design = Design.useOsStyle,
  }) async {
    dialogText ??= Text('You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}');
    final useAndroidDesign = design == Design.android || (design == Design.useOsStyle && Platform.isAndroid);
    final List<Widget> actions = [];

    final updateAction = () {
      launchAppStore(versionStatus.appStoreLink);

      if (allowDismissal) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    };

    if (allowDismissal) {
      dismissAction ??= () => Navigator.of(context, rootNavigator: true).pop();

      if(useAndroidDesign) {
        actions.add(TextButton(
          child: dismissButtonText,
          onPressed: dismissAction,
          style: dismissButtonStyle,
        ));
      } else {
        actions.add(CupertinoDialogAction(
          child: dismissButtonText,
          onPressed: dismissAction,
        ));
      }
    }

    if(useAndroidDesign){
      actions.add(TextButton(
        child: updateButtonText,
        onPressed: updateAction,
        style: updateButtonStyle,
      ));
    } else {
      actions.add(CupertinoDialogAction(
        child: updateButtonText,
        onPressed: updateAction,
        isDefaultAction: true,
      ));
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: allowDismissal,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () => Future.value(allowDismissal),
          child: useAndroidDesign
            ? AlertDialog(
                title: dialogTitle,
                content: dialogText,
                actions: actions,
              )
            : CupertinoAlertDialog(
                title: dialogTitle,
                content: dialogText,
                actions: actions,
              ),
        );
      },
    );
  }

  /// Launches the Apple App Store or Google Play Store page for the app.
  Future<void> launchAppStore(String appStoreLink) async {
    debugPrint(appStoreLink);
    if (await canLaunch(appStoreLink)) {
      await launch(appStoreLink);
    } else {
      throw Exception('Could not launch appStoreLink');
    }
  }
}
