import 'dart:io';
import 'package:chat_app/common/repositories/common_firebase_storage_repository.dart';
import 'package:chat_app/common/utils/utils.dart';
import 'package:chat_app/models/status_model.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// インスタのストーリー、LINEのタイムラインみたいなもの

final statusRepositoryProvider = Provider((ref) {
  return StatusRepository(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    ref: ref,
  );
});

class StatusRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ProviderRef ref;

  StatusRepository({
    required this.firestore,
    required this.auth,
    required this.ref,
  });

  // 現状では全ての画像にcreatedAtを入れてないのと削除機能がないのでストーリーとは少し違う
  void uoloadStatus({
    required String username,
    required String profilePic,
    required String phoneNumber,
    required File statusImage,
    required BuildContext context,
  }) async {
    try {
      var statusId = const Uuid().v1();
      String uid = auth.currentUser!.uid;
      String imageUrl = await ref
          .read(commonFirebaseStorageRepositoryProvider)
          .storeFileToFirebase(
            '/status/$statusId$uid',
            statusImage,
          );
      // 連絡先データを取得
      List<Contact> contacts = [];
      if (await FlutterContacts.requestPermission()) {
        contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
      }

      List<String> uidWhoCanSee = [];

      for (int i = 0; i < contacts.length; i++) {
        // 連絡先の電話番号とfirebaseに登録されている番号が一致したやつ
        var userDataFirebase = await firestore
            .collection('users')
            .where(
              'phoneNumber',
              isEqualTo: contacts[i].phones[0].number.replaceAll(
                    ' ',
                    '',
                  ),
            )
            .get();

        // あれば、そのデータを取得する
        if (userDataFirebase.docs.isNotEmpty) {
          var userData = UserModel.fromMap(
            userDataFirebase.docs[0].data(),
          );
          String uid = userData.uid;
          uidWhoCanSee.add(uid);
        }
      }

      List<String> statusImageUrls = [];

      // firebaseのステータスから自分のデータを取得
      var statusesSnapshot = await firestore
          .collection('status')
          .where(
            'uid',
            isEqualTo: auth.currentUser!.uid,
          )
          .get();

      if (statusesSnapshot.docs.isNotEmpty) {
        // データが既にあれば、そのデータを取得
        Status status = Status.fromMap(
          statusesSnapshot.docs[0].data(),
        );
        // 現在ある画像データを入れて
        statusImageUrls = status.photoUrl;
        // その後に追加した画像データを入れる
        statusImageUrls.add(imageUrl);

        // firebaseに登録
        await firestore
            .collection('status')
            .doc(statusesSnapshot.docs[0].id)
            .update({
          'photoUrl': statusImageUrls,
        });
        return; // 終わり
      } else {
        // 登録データがなければ（１日の中で初投稿）
        // 今回登録した画像URLを入れる
        statusImageUrls = [imageUrl];
      }

      // ステータスモデル型に変換して
      Status status = Status(
        uid: uid,
        username: username,
        phoneNumber: phoneNumber,
        photoUrl: statusImageUrls,
        createdAt: DateTime.now(),
        profilePic: profilePic,
        statusId: statusId,
        whoCanSee: uidWhoCanSee,
      );

      // firebaseに登録
      await firestore.collection('status').doc(statusId).set(
            status.toMap(),
          );
    } catch (e) {
      showSnackBar(context: context, content: e.toString());
    }
  }

  // ステータス（インスタのストーリーみたいな機能）を取得する
  Future<List<Status>> getStatus(BuildContext context) async {
    List<Status> statusData = [];
    try {
      // 連絡先データを取得
      List<Contact> contacts = [];
      if (await FlutterContacts.requestPermission()) {
        contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
      }
      for (int i = 0; i < contacts.length; i++) {
        // 連絡先の電話番号とfirebaseに登録されている番号が一致したやつ
        var statusesSnapshot = await firestore
            .collection('status')
            .where(
              'phoneNumber',
              isEqualTo: contacts[i].phones[0].number.replaceAll(
                    ' ',
                    '',
                  ),
            )
            // .where(
            //   // 24時間以内
            //   'createdAt',
            //   isGreaterThan: DateTime.now()
            //       .subtract(
            //         const Duration(
            //           hours: 24,
            //         ),
            //       )
            //       .millisecondsSinceEpoch,
            // )
            .get();

        // 09012041204　のが1個取れた

        for (var tempData in statusesSnapshot.docs) {
          // ステータス型に
          Status tempStatus = Status.fromMap(tempData.data());
          // 'whoCanSee'（見れる人）の中に自分のIDがあるか
          if (tempStatus.whoCanSee.contains(auth.currentUser!.uid)) {
            statusData.add(tempStatus);
          }
        }
      }
    } catch (e) {
      showSnackBar(context: context, content: e.toString());
    }
    return statusData;
  }
}
