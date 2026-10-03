import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mix/mix.dart';

import '../../helpers/testing_utils.dart';

void main() {
  group('Prop', () {
    test('value constructor stores direct value', () {
      final prop = Prop.value(42);

      expect(prop, PropMatcher.hasValues);
      expect(prop, isNot(PropMatcher.hasTokens));
      expect(prop, resolvesTo(42));
    });

    test('token constructor stores token reference', () {
      final token = TestToken<Color>('primary');
      final prop = Prop.token(token);

      expect(prop, isNot(PropMatcher.hasValues));
      expect(prop, PropMatcher.hasTokens);
      expect(prop, PropMatcher.isToken(token));
    });

    test('merge replaces source with other source', () {
      final prop1 = Prop.value(10);
      final prop2 = Prop.value(20);

      final merged = prop1.mergeProp(prop2);

      expect(merged, PropMatcher.hasValues);
      expect(merged, resolvesTo(20));
    });

    test('resolves direct values', () {
      final prop = Prop.value(42);
      final context = MockBuildContext();

      final resolved = prop.resolveProp(context);

      expect(resolved, equals(42));
    });

    test('merges value and token sources (universal accumulation)', () {
      final token = TestToken<int>('n');
      final p1 = Prop.value(1);
      final p2 = Prop.token(token);

      final merged = p1.mergeProp(p2);

      // With universal accumulation, both sources are preserved
      expect(merged, PropMatcher.hasValues);
      expect(merged, PropMatcher.hasTokens);
      expect(merged, PropMatcher.isToken(token));

      // But during resolution, token takes precedence
      final context = MockBuildContext(tokens: {token: 42});
      expect(merged, resolvesTo(42, context: context));
    });

    test('merges directives', () {
      // Intentionally pass an empty directives list to 'a' and verify it is preserved
      final a = Prop.value(1).directives(<Directive<int>>[]);
      final b = Prop.value(2);

      final merged = a.mergeProp(b);

      expect(merged.$directives, a.$directives); // preserved from a
    });

    test('throws when resolving without value or token', () {
      final p = const Prop<int>.directives([]);
      expect(
        () => p.resolveProp(MockBuildContext()),
        throwsA(isA<FlutterError>()),
      );
    });

    test('value handles null without crashing token-ref detection', () {
      final prop = Prop.value<int?>(null);

      expect(prop, PropMatcher.hasValues);
      expect(prop, isNot(PropMatcher.hasTokens));
      expect(prop.resolveProp(MockBuildContext()), isNull);
    });

    test('single source applies directives in declaration order', () {
      final prop = Prop.value(3).directives([
        MockDirective('double', (int value) => value * 2),
        MockDirective('increment', (int value) => value + 1),
      ]);

      expect(prop.resolveProp(MockBuildContext()), 7);
    });

    test('single token resolves again on each call before directives', () {
      var value = 2;
      final token = ContextToken<int>((_) => value);
      final prop = Prop.token(
        token,
      ).directives([MockDirective('double', (int value) => value * 2)]);
      final context = MockBuildContext();

      expect(prop.resolveProp(context), 4);
      value = 5;
      expect(prop.resolveProp(context), 10);
    });

    test('nullable single token keeps null for directives', () {
      final prop = Prop.token(
        ContextToken<int?>((_) => null),
      ).directives([MockDirective('default', (int? value) => value ?? 7)]);

      expect(prop.resolveProp(MockBuildContext()), 7);
    });
  });

  group('Long property merge chains', () {
    Prop<int> chain(int count) {
      var prop = Prop.value(0);
      for (var i = 1; i < count; i++) {
        prop = prop.mergeProp(Prop.value(i));
      }

      return prop;
    }

    test('preserves every source in order across both merge branches', () {
      final left = chain(64);
      final right = chain(64);
      final merged = left.mergeProp(right);
      final expected = [
        ...List.generate(64, (i) => ValueSource(i)),
        ...List.generate(64, (i) => ValueSource(i)),
      ];

      expect(merged.sources, expected);
      expect(merged.sources[63], ValueSource(63));
      expect(merged.sources[64], ValueSource(0));
      expect(merged.resolveProp(MockBuildContext()), 63);
      expect(merged, left.mergeProp(right));
    });

    test('merge snapshots detach from later mutations of either input', () {
      final left = chain(64);
      final right = Prop.value(64);
      final merged = left.mergeProp(right);

      left.sources[0] = const ValueSource(-1);
      left.sources.add(const ValueSource(-2));
      right.sources[0] = const ValueSource(-3);
      expect(merged.sources.first, ValueSource(0));
      expect(merged.sources.last, ValueSource(64));
      expect(merged.sources, hasLength(65));

      final next = merged.mergeProp(Prop.value(65));
      merged.sources
        ..removeRange(0, 2)
        ..insert(0, const ValueSource(-4))
        ..addAll([const ValueSource(-5)])
        ..replaceRange(1, 2, [const ValueSource(-6)]);
      expect(next.sources, List.generate(66, (i) => ValueSource(i)));
      expect(next.resolveProp(MockBuildContext()), 65);
      expect(merged.resolveProp(MockBuildContext()), -5);
    });

    test('deep chains resolve without recursive stack growth', () {
      final prop = chain(10000);

      expect(prop.sources, hasLength(10000));
      expect(prop.resolveProp(MockBuildContext()), 9999);
    });

    test('source list keeps native self insertion behavior and snapshots', () {
      for (final operation in [
        (List<PropSource<int>> sources) => sources.addAll(sources),
        (List<PropSource<int>> sources) => sources.insertAll(2, sources),
        (List<PropSource<int>> sources) => sources.replaceRange(2, 4, sources),
      ]) {
        final prop = chain(64);
        final snapshot = prop.mergeProp(Prop.value(64));
        final expected = List<PropSource<int>>.of(prop.sources);
        Object? expectedError;
        try {
          operation(expected);
        } catch (error) {
          expectedError = error;
        }
        if (expectedError == null) {
          operation(prop.sources);
          expect(prop.sources, expected);
        } else {
          expect(
            () => operation(prop.sources),
            throwsA(
              predicate<Object>(
                (error) => error.runtimeType == expectedError.runtimeType,
                'the native list error type',
              ),
            ),
          );
        }

        expect(snapshot.sources, List.generate(65, (i) => ValueSource(i)));
      }
    });

    test('long mixed chains preserve value conversion and partial merging', () {
      var prop = Prop.value<EdgeInsetsGeometry>(const EdgeInsets.all(0));
      for (var i = 1; i < 64; i++) {
        prop = prop.mergeProp(
          i.isEven
              ? Prop.value<EdgeInsetsGeometry>(EdgeInsets.all(i.toDouble()))
              : Prop.mix<EdgeInsetsGeometry>(EdgeInsetsMix(left: i.toDouble())),
        );
      }

      expect(
        prop.resolveProp(MockBuildContext()),
        const EdgeInsets.fromLTRB(63, 62, 62, 62),
      );
    });

    test('overridden tokens still resolve in order before the last value', () {
      final calls = <int>[];
      var prop = Prop.value(-1);
      for (var i = 0; i < 64; i++) {
        prop = prop.mergeProp(
          Prop.token(
            ContextToken<int>((_) {
              calls.add(i);

              return i;
            }),
          ),
        );
      }
      prop = prop.mergeProp(Prop.value(99));

      expect(prop.resolveProp(MockBuildContext()), 99);
      expect(calls, List.generate(64, (i) => i));
    });
  });

  group('Prop with Mix values', () {
    test('value constructor stores Mix value', () {
      final mixValue = MockMix<int>(42);
      final prop = Prop.mix(mixValue);

      expect(prop, resolvesTo(42));
    });

    test('merge combines Mix values', () {
      final mix1 = MockMix<int>(10, merger: (a, b) => a + b);
      final mix2 = MockMix<int>(20, merger: (a, b) => a + b);

      final prop1 = Prop.mix(mix1);
      final prop2 = Prop.mix(mix2);

      final merged = prop1.mergeProp(prop2);

      expect(merged, resolvesTo(30));
    });

    test('resolves Mix values', () {
      final mixValue = MockMix<int>(42);
      final prop = Prop.mix(mixValue);
      final context = MockBuildContext();

      final resolved = prop.resolveProp(context);

      expect(resolved, equals(42));
    });
  });

  group('Prop no auto-conversion behavior', () {
    test('Prop.value does NOT auto-convert to Mix', () {
      // Register converter
      MixConverterRegistry.instance.register(TextStyleConverter());

      // Create prop with regular value
      final prop = Prop.value(const TextStyle(fontSize: 16));

      // Should be ValueSource, NOT MixSource
      expect(prop, PropMatcher.hasValues);
      expect(prop, isNot(PropMatcher.hasMixes));
    });

    test('Prop.mix creates MixSource', () {
      final mix = TextStyleMix(fontSize: 16);
      final prop = Prop.mix(mix);

      expect(prop, PropMatcher.hasMixes);
    });

    test('Conversion happens during resolution with Mix values', () {
      // Register converter
      MixConverterRegistry.instance.register(TextStyleConverter());

      final prop1 = Prop.value(const TextStyle(fontSize: 16));
      final prop2 = Prop.mix(TextStyleMix(color: Colors.red));
      final merged = prop1.mergeProp(prop2);

      // Sources are not converted yet
      expect(merged, PropMatcher.hasValues);
      expect(merged, PropMatcher.hasMixes);

      // Conversion happens during resolution
      final context = MockBuildContext();
      final resolved = merged.resolveProp(context);
      expect(resolved.fontSize, 16);
      expect(resolved.color, Colors.red);
    });

    test('No Mix values means no conversion', () {
      final prop1 = Prop.value(Colors.red);
      final prop2 = Prop.value(Colors.blue);
      final merged = prop1.mergeProp(prop2);

      // No converter should be called
      final context = MockBuildContext();
      final resolved = merged.resolveProp(context);
      expect(resolved, Colors.blue); // Last value wins
    });

    test('Mixed regular and Mix values are properly converted and merged', () {
      // Register converter
      MixConverterRegistry.instance.register(EdgeInsetsConverter());

      // Create props with mixed types - simpler test case
      final prop1 = Prop.value(const EdgeInsets.all(8.0));
      final prop2 = Prop.mix(EdgeInsetsMix(left: 16.0, top: 20.0));

      // Merge props
      final merged = prop1.mergeProp(prop2);

      // Resolution should convert regular values and merge with Mix
      final context = MockBuildContext();
      final resolved = merged.resolveProp(context);

      // The Mix values should take precedence where specified
      // prop1 converted: all sides = 8.0
      // prop2 Mix: left = 16.0, top = 20.0
      // Merged result takes Mix values where specified
      expect(resolved.left, 16.0); // from Mix
      expect(resolved.top, 20.0); // from Mix
      expect(resolved.right, 8.0); // from converted prop1
      expect(resolved.bottom, 8.0); // from converted prop1
    });
  });
}
