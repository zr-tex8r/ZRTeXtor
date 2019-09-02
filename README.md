ZRTeXtor モジュール
===================

TeX 関連のデータファイルを操作する為の Perl モジュール。作者（ZR）が配布
している Perl で書かれたツールを実行するのに必要となる。

このモジュールを用いた自作のプログラムを作成および配布するのは自由である
が、残念ながら、機能の解説をす余裕は全くない。(ソースコード中のコメントに
ある程度の説明があるが。)

更新履歴
--------

  * Version 1.7.0 〈2019/09/02〉
      - 最近の (u)ptftopl の挙動の変更に追随した。
      - バグ修正(vf_divide_zvp)。
  * Version 1.6.0 〈2019/02/25〉
      - 非 strict モードでは charpacket 欠落のエラーも抑止する。
  * Version 1.5.0 〈2018/01/21〉
      - upTeX ツール非使用時に、CHARSINTYPE 中の 16 ビット超の符号値を
        サポートした。  
        ※upTeX ツール使用時はそのツールが対応しているかに依存する。
  * Version 1.4.1 〈2018/01/20〉
      - バグ修正(vf_parse)。
  * Version 1.4.0 〈2017/07/17〉
      - バグ修正。
  * Version 1.3.0 〈2010/05/05〉
      - 最初の公開版。

--------------------
Takayuki YATO (aka. "ZR")  
https://github.com/zr-tex8r
