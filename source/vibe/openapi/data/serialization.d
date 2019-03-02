module vibe.openapi.data.serialization;

import vibe.internal.meta.traits;
import vibe.internal.meta.uda;

import std.array : Appender, appender;
import std.conv : to;
import std.exception : enforce;
import std.traits;
import std.typecons : Flag;
import std.typetuple;


/**
	Serializes a value with the given serializer.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
auto serialize(Serializer, T, ARGS...)(T value, ARGS args)
{
	auto serializer = Serializer(args);
	serialize(serializer, value);
	return serializer.getSerializedResult();
}
/// ditto
void serialize(Serializer, T)(ref Serializer serializer, T value)
{
	serializeWithPolicy!(Serializer, DefaultPolicy)(serializer, value);
}

/**
	Serializes a value with the given serializer, representing values according to `Policy` when possible.

	The serializer must have a value result for the first form
	to work. Otherwise, use the range based form.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
auto serializeWithPolicy(Serializer, alias Policy, T, ARGS...)(T value, ARGS args)
{
	auto serializer = Serializer(args);
	serializeWithPolicy!(Serializer, Policy)(serializer, value);
	return serializer.getSerializedResult();
}
/// ditto
void serializeWithPolicy(Serializer, alias Policy, T)(ref Serializer serializer, T value)
{
	static if (is(typeof(serializer.beginWriteDocument!T())))
		serializer.beginWriteDocument!T();
	serializeValueImpl!(Serializer, Policy).serializeValue!T(serializer, value);
	static if (is(typeof(serializer.endWriteDocument!T())))
		serializer.endWriteDocument!T();
}

/**
	Deserializes and returns a serialized value.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
T deserialize(Serializer, T, ARGS...)(ARGS args)
{
	return deserializeWithPolicy!(Serializer, DefaultPolicy, T)(args);
}

/**
	Deserializes and returns a serialized value, interpreting values according to `Policy` when possible.

	serialized_data can be either an input range or a value containing
	the serialized data, depending on the type of serializer used.

	See_Also: `vibe.data.json.JsonSerializer`, `vibe.data.json.JsonStringSerializer`, `vibe.data.bson.BsonSerializer`
*/
T deserializeWithPolicy(Serializer, alias Policy, T, ARGS...)(ARGS args)
{
	auto deserializer = Serializer(args);
	return deserializeValueImpl!(Serializer, Policy).deserializeValue!T(deserializer);
}

private template serializeValueImpl(Serializer, alias Policy) {
	alias _Policy = Policy;
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	// work around https://issues.dlang.org/show_bug.cgi?id=16528
	static if (isSafeSerializer!Serializer) {
		void serializeValue(T, ATTRIBUTES...)(ref Serializer ser, T value) @safe { serializeValueDeduced!(T, ATTRIBUTES)(ser, value); }
	} else {
		void serializeValue(T, ATTRIBUTES...)(ref Serializer ser, T value) { serializeValueDeduced!(T, ATTRIBUTES)(ser, value); }
	}

	private void serializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser, T value)
	{
		import std.typecons : BitFlags, Nullable, Tuple, Typedef, TypedefType, tuple;

		alias TU = Unqual!T;

		alias Traits = .Traits!(TU, _Policy, ATTRIBUTES);

		static if (isPolicySerializable!(Policy, TU)) {
			alias CustomType = typeof(Policy!TU.toRepresentation(TU.init));
			ser.serializeValue!(CustomType, ATTRIBUTES)(Policy!TU.toRepresentation(value));
		} else static if (is(TU == enum)) {
			static if (hasPolicyAttributeL!(ByNameAttribute, Policy, ATTRIBUTES)) {
				ser.serializeValue!(string)(value.to!string());
			} else {
				ser.serializeValue!(OriginalType!TU)(cast(OriginalType!TU)value);
			}
		} else static if (Serializer.isSupportedValueType!TU) {
			static if (is(TU == typeof(null))) ser.writeValue!Traits(null);
			else ser.writeValue!(Traits, TU)(value);
		} else static if (/*isInstanceOf!(Tuple, TU)*/is(T == Tuple!TPS, TPS...)) {
			import std.algorithm.searching: all;
			static if (all!"!a.empty"([TU.fieldNames]) &&
					   !hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				static if (__traits(compiles, ser.beginWriteDictionary!TU(0))) {
					auto nfields = value.length;
					ser.beginWriteDictionary!Traits(nfields);
				} else {
					ser.beginWriteDictionary!Traits();
				}
				foreach (i, TV; TU.Types) {
					alias STraits = SubTraits!(Traits, TV);
					ser.beginWriteDictionaryEntry!STraits(underscoreStrip(TU.fieldNames[i]));
					ser.serializeValue!(TV, ATTRIBUTES)(value[i]);
					ser.endWriteDictionaryEntry!STraits(underscoreStrip(TU.fieldNames[i]));
				}
				static if (__traits(compiles, ser.endWriteDictionary!TU(0))) {
					ser.endWriteDictionary!Traits(nfields);
				} else {
					ser.endWriteDictionary!Traits();
				}
			} else static if (TU.Types.length == 1) {
				ser.serializeValue!(typeof(value[0]), ATTRIBUTES)(value[0]);
			} else {
				ser.beginWriteArray!Traits(value.length);
				foreach (i, TV; T.Types) {
					alias STraits = SubTraits!(Traits, TV);
					ser.beginWriteArrayEntry!STraits(i);
					ser.serializeValue!(TV, ATTRIBUTES)(value[i]);
					ser.endWriteArrayEntry!STraits(i);
				}
				ser.endWriteArray!Traits();
			}
		} else static if (isArray!TU) {
			alias TV = typeof(value[0]);
			alias STraits = SubTraits!(Traits, TV);
			ser.beginWriteArray!Traits(value.length);
			foreach (i, ref el; value) {
				ser.beginWriteArrayEntry!STraits(i);
				ser.serializeValue!(TV, ATTRIBUTES)(el);
				ser.endWriteArrayEntry!STraits(i);
			}
			ser.endWriteArray!Traits();
		} else static if (isAssociativeArray!TU) {
			alias TK = KeyType!TU;
			alias TV = ValueType!TU;
			alias STraits = SubTraits!(Traits, TV);

			static if (__traits(compiles, ser.beginWriteDictionary!TU(0))) {
				auto nfields = value.length;
				ser.beginWriteDictionary!Traits(nfields);
			} else {
				ser.beginWriteDictionary!Traits();
			}
			foreach (key, ref el; value) {
				string keyname;
				static if (is(TK : string)) keyname = key;
				else static if (is(TK : real) || is(TK : long) || is(TK == enum)) keyname = key.to!string;
				else static if (isStringSerializable!TK) keyname = key.toString();
				else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
				ser.beginWriteDictionaryEntry!STraits(keyname);
				ser.serializeValue!(TV, ATTRIBUTES)(el);
				ser.endWriteDictionaryEntry!STraits(keyname);
			}
			static if (__traits(compiles, ser.endWriteDictionary!TU(0))) {
				ser.endWriteDictionary!Traits(nfields);
			} else {
				ser.endWriteDictionary!Traits();
			}
		} else static if (/*isInstanceOf!(Nullable, TU)*/is(T == Nullable!TPS, TPS...)) {
			if (value.isNull()) ser.serializeValue!(typeof(null))(null);
			else ser.serializeValue!(typeof(value.get()), ATTRIBUTES)(value.get());
		} else static if (isInstanceOf!(Typedef, TU)) {
			ser.serializeValue!(TypedefType!TU, ATTRIBUTES)(cast(TypedefType!TU)value);
		} else static if (is(TU == BitFlags!E, E)) {
			alias STraits = SubTraits!(Traits, E);

			size_t cnt = 0;
			foreach (v; EnumMembers!E)
				if (value & v)
					cnt++;

			ser.beginWriteArray!Traits(cnt);
			cnt = 0;
			foreach (v; EnumMembers!E)
				if (value & v) {
					ser.beginWriteArrayEntry!STraits(cnt);
					ser.serializeValue!(E, ATTRIBUTES)(v);
					ser.endWriteArrayEntry!STraits(cnt);
					cnt++;
				}
			ser.endWriteArray!Traits();
		} else static if (isCustomSerializable!TU) {
			alias CustomType = typeof(T.init.toRepresentation());
			ser.serializeValue!(CustomType, ATTRIBUTES)(value.toRepresentation());
		} else static if (isISOExtStringSerializable!TU) {
			ser.serializeValue!(string, ATTRIBUTES)(value.toISOExtString());
		} else static if (isStringSerializable!TU) {
			ser.serializeValue!(string, ATTRIBUTES)(value.toString());
		} else static if (is(TU == struct) || is(TU == class)) {
			static if (!hasSerializableFields!(TU, Policy))
				pragma(msg, "Serializing composite type "~T.stringof~" which has no serializable fields");
			static if (is(TU == class)) {
				if (value is null) {
					ser.serializeValue!(typeof(null))(null);
					return;
				}
			}
			static auto safeGetMember(string mname)(ref T val) @safe {
				static if (__traits(compiles, __traits(getMember, val, mname))) {
					return __traits(getMember, val, mname);
				} else {
					pragma(msg, "Warning: Getter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
					return () @trusted { return __traits(getMember, val, mname); } ();
				}
			}
			static if (hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				enum nfields = getExpandedFieldCount!(TU, SerializableFields!(TU, Policy));
				ser.beginWriteArray!Traits(nfields);
				size_t fcount = 0;
				foreach (mname; SerializableFields!(TU, Policy)) {
					alias TMS = TypeTuple!(typeof(__traits(getMember, value, mname)));
					foreach (j, TM; TMS) {
						alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[j]));
						alias STraits = SubTraits!(Traits, TM, TA);
						ser.beginWriteArrayEntry!STraits(fcount);
						static if (!isBuiltinTuple!(T, mname))
							ser.serializeValue!(TM, TA)(safeGetMember!mname(value));
						else
							ser.serializeValue!(TM, TA)(tuple(__traits(getMember, value, mname))[j]);
						ser.endWriteArrayEntry!STraits(fcount);
						fcount++;
					}
				}
				ser.endWriteArray!Traits();
			} else {
				static if (__traits(compiles, ser.beginWriteDictionary!Traits(0))) {
					enum nfields = getExpandedFieldCount!(TU, SerializableFields!(TU, Policy));
					ser.beginWriteDictionary!Traits(nfields);
				} else {
					ser.beginWriteDictionary!Traits();
				}
				foreach (mname; SerializableFields!(TU, Policy)) {
					alias TM = TypeTuple!(typeof(__traits(getMember, TU, mname)));
					alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[0]));
					enum name = getPolicyAttribute!(TU, mname, NameAttribute, Policy)(NameAttribute!DefaultPolicy(underscoreStrip(mname))).name;
					static if (!isBuiltinTuple!(T, mname))
						auto vt = safeGetMember!mname(value);
					else
						auto vt = tuple!TM(__traits(getMember, value, mname));
					enum opt = getPolicyAttribute!(TU, mname, OptionalAttribute, Policy)(OptionalAttribute!DefaultPolicy(OptionalDirection.req)).direction;

					//skip optional attributes from serialization
					if ((opt & OptionalDirection.out_) == OptionalDirection.out_) {
						import vibe.openapi.data.json : Json;
						static if (isInstanceOf!(Nullable, typeof(vt))) {
							if (vt.isNull) continue;
						} else static if (is(typeof(vt) == Json)) {
							if (vt.type == Json.Type.undefined || vt.type == Json.Type.null_ || (vt.type == Json.Type.object && !vt.length)) continue;
						} else static if (is(typeof(vt) == class)) {
							if (vt is null) continue;
						} else {
							// workaround for unsafe opEquals
							static if (!isSafeSerializer!Serializer || __traits(compiles, () @safe { return vt == typeof(vt).init; }())) {
								if (vt == typeof(vt).init) continue;
							} else {
								if (() @trusted { return vt == typeof(vt).init; }()) continue;
							}
						}
					}
					alias STraits = SubTraits!(Traits, typeof(vt), TA);
					ser.beginWriteDictionaryEntry!STraits(name);
					ser.serializeValue!(typeof(vt), TA)(vt);
					ser.endWriteDictionaryEntry!STraits(name);
				}
				static if (__traits(compiles, ser.endWriteDictionary!Traits(0))) {
					ser.endWriteDictionary!Traits(nfields);
				} else {
					ser.endWriteDictionary!Traits();
				}
			}
		} else static if (isPointer!TU) {
			if (value is null) {
				ser.writeValue!Traits(null);
				return;
			}
			ser.serializeValue!(PointerTarget!TU)(*value);
		} else static if (is(TU == bool) || is(TU : real) || is(TU : long)) {
			ser.serializeValue!(string, ATTRIBUTES)(to!string(value));
		} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
	}
}

private struct Traits(T, alias POL, ATTRIBUTES...)
{
	alias Type = T;
	alias Policy = POL;
	alias Attributes = TypeTuple!ATTRIBUTES;
}

private struct SubTraits(Traits, T, A...)
{
	alias Type = Unqual!T;
	alias Attributes = TypeTuple!A;
	alias Policy = Traits.Policy;
	alias ContainerType = Traits.Type;
	alias ContainerAttributes = Traits.Attributes;
}

private template deserializeValueImpl(Serializer, alias Policy) {
	alias _Policy = Policy;
	static assert(Serializer.isSupportedValueType!string, "All serializers must support string values.");
	static assert(Serializer.isSupportedValueType!(typeof(null)), "All serializers must support null values.");

	// work around https://issues.dlang.org/show_bug.cgi?id=16528
	static if (isSafeSerializer!Serializer) {
		T deserializeValue(T, ATTRIBUTES...)(ref Serializer ser) @safe { return deserializeValueDeduced!(T, ATTRIBUTES)(ser); }
	} else {
		T deserializeValue(T, ATTRIBUTES...)(ref Serializer ser) { return deserializeValueDeduced!(T, ATTRIBUTES)(ser); }
	}

	T deserializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser) if(!isMutable!T)
	{
		import std.algorithm.mutation : move;
		auto ret = deserializeValue!(Unqual!T, ATTRIBUTES)(ser);
		return () @trusted { return cast(T)ret.move; } ();
	}

	T deserializeValueDeduced(T, ATTRIBUTES...)(ref Serializer ser) if(isMutable!T)
	{
		import std.typecons : BitFlags, Nullable, Typedef, TypedefType, Tuple;

		alias Traits = .Traits!(T, _Policy, ATTRIBUTES);

		static if (isPolicySerializable!(Policy, T)) {
			alias CustomType = typeof(Policy!T.toRepresentation(T.init));
			return Policy!T.fromRepresentation(ser.deserializeValue!(CustomType, ATTRIBUTES));
		} else static if (is(T == enum)) {
			static if (hasPolicyAttributeL!(ByNameAttribute, Policy, ATTRIBUTES)) {
				return ser.deserializeValue!(string, ATTRIBUTES).to!T();
			} else {
				return cast(T)ser.deserializeValue!(OriginalType!T);
			}
		} else static if (Serializer.isSupportedValueType!T) {
			return ser.readValue!(Traits, T)();
		} else static if (/*isInstanceOf!(Tuple, TU)*/is(T == Tuple!TPS, TPS...)) {
			enum fieldsCount = T.Types.length;
			import std.algorithm.searching: all;
			static if (all!"!a.empty"([T.fieldNames]) &&
					   !hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				T ret;
				bool[fieldsCount] set;
				ser.readDictionary!Traits((name) {
					switch (name) {
						default: break;
						foreach (i, TV; T.Types) {
							enum fieldName = underscoreStrip(T.fieldNames[i]);
							alias STraits = SubTraits!(Traits, TV);
							case fieldName: {
								ser.beginReadDictionaryEntry!STraits(fieldName);
								ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
								ser.endReadDictionaryEntry!STraits(fieldName);
								set[i] = true;
							} break;
						}
					}
				});
				foreach (i, fieldName; T.fieldNames)
					enforce(set[i], "Missing tuple field '"~fieldName~"' of type '"~T.Types[i].stringof~"' ("~Policy.stringof~").");
				return ret;
			} else static if (fieldsCount == 1) {
				return T(ser.deserializeValue!(T.Types[0], ATTRIBUTES)());
			} else {
				T ret;
				size_t currentField = 0;
				ser.readArray!Traits((sz) { assert(sz == 0 || sz == fieldsCount); }, {
					switch (currentField++) {
						default: break;
						foreach (i, TV; T.Types) {
							alias STraits = SubTraits!(Traits, TV);
							case i: {
								ser.beginReadArrayEntry!STraits(i);
								ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
								ser.endReadArrayEntry!STraits(i);
							} break;
						}
					}
				});
				enforce(currentField == fieldsCount, "Missing tuple field(s) - expected '"~fieldsCount.stringof~"', received '"~currentField.stringof~"' ("~Policy.stringof~").");
				return ret;
			}
		} else static if (isStaticArray!T) {
			alias TV = typeof(T.init[0]);
			alias STraits = SubTraits!(Traits, TV);
			T ret;
			size_t i = 0;
			ser.readArray!Traits((sz) { assert(sz == 0 || sz == T.length); }, {
				assert(i < T.length);
				ser.beginReadArrayEntry!STraits(i);
				ret[i] = ser.deserializeValue!(TV, ATTRIBUTES);
				ser.endReadArrayEntry!STraits(i);
				i++;
			});
			return ret;
		} else static if (isDynamicArray!T) {
			alias TV = typeof(T.init[0]);
			alias STraits = SubTraits!(Traits, TV);
			//auto ret = appender!T();
			T ret; // Cannot use appender because of DMD BUG 10690/10859/11357
			ser.readArray!Traits((sz) @safe { ret.reserve(sz); }, () @safe {
				size_t i = ret.length;
				ser.beginReadArrayEntry!STraits(i);
				static if (__traits(compiles, () @safe { ser.deserializeValue!(TV, ATTRIBUTES); }))
					ret ~= ser.deserializeValue!(TV, ATTRIBUTES);
				else // recursive array https://issues.dlang.org/show_bug.cgi?id=16528
					ret ~= (() @trusted => ser.deserializeValue!(TV, ATTRIBUTES))();
				ser.endReadArrayEntry!STraits(i);
			});
			return ret;//cast(T)ret.data;
		} else static if (isAssociativeArray!T) {
			alias TK = KeyType!T;
			alias TV = ValueType!T;
			alias STraits = SubTraits!(Traits, TV);

			T ret;
			ser.readDictionary!Traits((name) @safe {
				TK key;
				static if (is(TK == string) || (is(TK == enum) && is(OriginalType!TK == string))) key = cast(TK)name;
				else static if (is(TK : real) || is(TK : long) || is(TK == enum)) key = name.to!TK;
				else static if (isStringSerializable!TK) key = TK.fromString(name);
				else static assert(false, "Associative array keys must be strings, numbers, enums, or have toString/fromString methods.");
				ser.beginReadDictionaryEntry!STraits(name);
				ret[key] = ser.deserializeValue!(TV, ATTRIBUTES);
				ser.endReadDictionaryEntry!STraits(name);
			});
			return ret;
		} else static if (isInstanceOf!(Nullable, T)) {
			if (ser.tryReadNull!Traits()) return T.init;
			return T(ser.deserializeValue!(typeof(T.init.get()), ATTRIBUTES));
		} else static if (isInstanceOf!(Typedef, T)) {
			return T(ser.deserializeValue!(TypedefType!T, ATTRIBUTES));
		} else static if (is(T == BitFlags!E, E)) {
			alias STraits = SubTraits!(Traits, E);
			T ret;
			size_t i = 0;
			ser.readArray!Traits((sz) {}, {
				ser.beginReadArrayEntry!STraits(i);
				ret |= ser.deserializeValue!(E, ATTRIBUTES);
				ser.endReadArrayEntry!STraits(i);
				i++;
			});
			return ret;
		} else static if (isCustomSerializable!T) {
			alias CustomType = typeof(T.init.toRepresentation());
			return T.fromRepresentation(ser.deserializeValue!(CustomType, ATTRIBUTES));
		} else static if (isISOExtStringSerializable!T) {
			return T.fromISOExtString(ser.readValue!(Traits, string)());
		} else static if (isStringSerializable!T) {
			return T.fromString(ser.readValue!(Traits, string)());
		} else static if (is(T == struct) || is(T == class)) {
			static if (is(T == class)) {
				if (ser.tryReadNull!Traits()) return null;
			}

			T ret;
			string name;
			bool[getExpandedFieldsData!(T, SerializableFields!(T, Policy)).length] set;
			static if (is(T == class)) ret = new T;

			void safeSetMember(string mname, U)(ref T value, U fval)
			@safe {
				static if (__traits(compiles, () @safe { __traits(getMember, value, mname) = fval; }))
					__traits(getMember, value, mname) = fval;
				else {
					pragma(msg, "Warning: Setter for "~fullyQualifiedName!T~"."~mname~" is not @safe");
					() @trusted { __traits(getMember, value, mname) = fval; } ();
				}
			}

			static if (hasPolicyAttributeL!(AsArrayAttribute, Policy, ATTRIBUTES)) {
				size_t idx = 0;
				ser.readArray!Traits((sz){}, {
					static if (hasDeserializableFields!(T, Policy)) {
						switch (idx++) {
							default: break;
							foreach (i, FD; getExpandedFieldsData!(T, DeserializableFields!(T, Policy))) {
								enum mname = FD[0];
								enum msindex = FD[1];
								alias MT = TypeTuple!(__traits(getMember, T, mname));
								alias MTI = MT[msindex];
								alias TMTI = typeof(MTI);
								alias TMTIA = TypeTuple!(__traits(getAttributes, MTI));
								alias STraits = SubTraits!(Traits, TMTI, TMTIA);

							case i:
								static if (hasPolicyAttribute!(OptionalAttribute, Policy, MTI))
									if (ser.tryReadNull!STraits()) return;
								set[i] = true;
								ser.beginReadArrayEntry!STraits(i);
								static if (!isBuiltinTuple!(T, mname)) {
									safeSetMember!mname(ret, ser.deserializeValue!(TMTI, TMTIA));
								} else {
									__traits(getMember, ret, mname)[msindex] = ser.deserializeValue!(TMTI, TMTIA);
								}
								ser.endReadArrayEntry!STraits(i);
								break;
							}
						}
					} else {
						pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
					}
				});
			} else {
				ser.readDictionary!Traits((name) {
					static if (hasDeserializableFields!(T, Policy)) {
						switch (name) {
							default: break;
							foreach (i, mname; DeserializableFields!(T, Policy)) {
								alias TM = TypeTuple!(typeof(__traits(getMember, T, mname)));
								alias TA = TypeTuple!(__traits(getAttributes, TypeTuple!(__traits(getMember, T, mname))[0]));
								alias STraits = SubTraits!(Traits, TM, TA);
								enum fname = getPolicyAttribute!(T, mname, NameAttribute, Policy)(NameAttribute!DefaultPolicy(underscoreStrip(mname))).name;
								case fname:
									static if (hasPolicyAttribute!(OptionalAttribute, Policy, TypeTuple!(__traits(getMember, T, mname))[0]))
										if (ser.tryReadNull!STraits()) return;
									set[i] = true;
									ser.beginReadDictionaryEntry!STraits(fname);
									static if (!isBuiltinTuple!(T, mname)) {
										safeSetMember!mname(ret, ser.deserializeValue!(TM, TA));
									} else {
										__traits(getMember, ret, mname) = ser.deserializeValue!(Tuple!TM, TA);
									}
									ser.endReadDictionaryEntry!STraits(fname);
									break;
							}
						}
					} else {
						pragma(msg, "Deserializing composite type "~T.stringof~" which has no serializable fields.");
					}
				});
			}

			foreach (i, mname; DeserializableFields!(T, Policy))
				static if (!hasPolicyAttribute!(OptionalAttribute, Policy, TypeTuple!(__traits(getMember, T, mname))[0]))
					enforce(set[i], "Missing non-optional field '"~mname~"' of type '"~T.stringof~"' ("~Policy.stringof~").");
				else {
					enum dir = getPolicyAttribute!(T, mname, OptionalAttribute, Policy)(OptionalAttribute!DefaultPolicy(OptionalDirection.req)).direction;
					enforce(set[i] || ((dir & OptionalDirection.in_) == OptionalDirection.in_),
						"Missing non-optional field '"~mname~"' of type '"~T.stringof~"' ("~Policy.stringof~").");
				}
			return ret;
		} else static if (isPointer!T) {
			if (ser.tryReadNull!Traits()) return null;
			alias PT = PointerTarget!T;
			auto ret = new PT;
			*ret = ser.deserializeValue!(PT, ATTRIBUTES);
			return ret;
		} else static if (is(T == bool) || is(T : real) || is(T : long)) {
			return to!T(ser.deserializeValue!string());
		} else static assert(false, "Unsupported serialization type: " ~ T.stringof);
	}
}


/**
	Attribute for overriding the field name during (de-)serialization.

	Note that without the `@name` attribute there is a shorter alternative
	for using names that collide with a D keyword. A single trailing
	underscore will automatically be stripped when determining a field
	name.
*/
NameAttribute!Policy name(alias Policy = DefaultPolicy)(string name)
{
	return NameAttribute!Policy(name);
}

/**
	Attribute marking a field as optional during de/serialization.
	It is possible to fine tune the direction of attribute:
		@optional!In - it is optional only during deserialization
		@optional!Out - it is optional only during serialization
		@optional!InOut - optional both way - default
*/
@property OptionalAttribute!Policy optional(D = InOut, alias Policy = DefaultPolicy)()
	if (is(D == In) || is(D == Out) || is(D == InOut))
{
	static if (is(D == In)) {
		return OptionalAttribute!Policy(OptionalDirection.in_);
	}
	else static if (is(D == Out)) {
		return OptionalAttribute!Policy(OptionalDirection.out_);
	}
	else return OptionalAttribute!Policy(OptionalDirection.inout_);
}

/**
	Attribute for marking non-serialized fields.
	It is possible to fine tune the direction of attribute:
		@ignore!In - it is ignored only during deserialization
		@ignore!Out - it is ignored only during serialization
		@ignore!InOut - ignored both way - default
*/
@property IgnoreAttribute!Policy ignore(D = InOut, alias Policy = DefaultPolicy)()
	if (is(D == In) || is(D == Out) || is(D == InOut))
{
	static if (is(D == In)) {
		return IgnoreAttribute!Policy(IgnoreDirection.in_);
	}
	else static if (is(D == Out)) {
		return IgnoreAttribute!Policy(IgnoreDirection.out_);
	}
	else return IgnoreAttribute!Policy(IgnoreDirection.inout_);
}

/**
	Attribute for forcing serialization of enum fields by name instead of by value.
*/
@property ByNameAttribute!Policy byName(alias Policy = DefaultPolicy)()
{
	return ByNameAttribute!Policy();
}

/**
	Attribute for representing a struct/class as an array instead of an object.

	Usually structs and class objects are serialized as dictionaries mapping
	from field name to value. Using this attribute, they will be serialized
	as a flat array instead. Note that changing the layout will make any
	already serialized data mismatch when this attribute is used.
*/
@property AsArrayAttribute!Policy asArray(alias Policy = DefaultPolicy)()
{
	return AsArrayAttribute!Policy();
}

///
enum FieldExistence
{
	missing,
	exists,
	defer
}

///
enum OptionalDirection
{
	req = 0,
	in_ = 1 << 0,
	out_ = 1 << 1,
	inout_ = in_ | out_
}

///
alias IgnoreDirection = OptionalDirection;

/// Aliases to simplify setting the direction of optional attribute
alias In = Flag!"In";
alias Out = Flag!"Out";
alias InOut = Flag!"InOut";

/// User defined attribute (not intended for direct use)
struct NameAttribute(alias POLICY) { alias Policy = POLICY; string name; }
/// ditto
struct OptionalAttribute(alias POLICY) { alias Policy = POLICY; OptionalDirection direction = OptionalDirection.inout_; }
/// ditto
struct IgnoreAttribute(alias POLICY) { alias Policy = POLICY; IgnoreDirection direction = IgnoreDirection.inout_; }
/// ditto
struct ByNameAttribute(alias POLICY) { alias Policy = POLICY; }
/// ditto
struct AsArrayAttribute(alias POLICY) { alias Policy = POLICY; }

/**
	Checks if a given type has a custom serialization representation.

	A class or struct type is custom serializable if it defines a pair of
	`toRepresentation`/`fromRepresentation` methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's `toRepresentation` method instead of the original value.

	This trait has precedence over `isISOExtStringSerializable` and
	`isStringSerializable`.
*/
template isCustomSerializable(T)
{
	enum bool isCustomSerializable = is(typeof(T.init.toRepresentation())) && is(typeof(T.fromRepresentation(T.init.toRepresentation())) == T);
}

/**
	Checks if a given type has an ISO extended string serialization representation.

	A class or struct type is ISO extended string serializable if it defines a
	pair of `toISOExtString`/`fromISOExtString` methods. Any class or
	struct type that has this trait will be serialized by using the return
	value of it's `toISOExtString` method instead of the original value.

	This is mainly useful for supporting serialization of the the date/time
	types in `std.datetime`.

	This trait has precedence over `isStringSerializable`.
*/
template isISOExtStringSerializable(T)
{
	enum bool isISOExtStringSerializable = is(typeof(T.init.toISOExtString()) == string) && is(typeof(T.fromISOExtString("")) == T);
}

/**
	Checks if a given type has a string serialization representation.

	A class or struct type is string serializable if it defines a pair of
	`toString`/`fromString` methods. Any class or struct type that
	has this trait will be serialized by using the return value of it's
	`toString` method instead of the original value.
*/
template isStringSerializable(T)
{
	enum bool isStringSerializable = is(typeof(T.init.toString()) == string) && is(typeof(T.fromString("")) == T);
}

/** Default policy (performs no customization).
*/
template DefaultPolicy(T)
{
}

/**
	Checks if a given policy supports custom serialization for a given type.

	A class or struct type is custom serializable according to a policy if
	the policy defines a pair of `toRepresentation`/`fromRepresentation`
	functions. Any class or struct type that has this trait for the policy supplied to
	`serializeWithPolicy` will be serialized by using the return value of the
	policy `toRepresentation` function instead of the original value.

	This trait has precedence over `isCustomSerializable`,
	`isISOExtStringSerializable` and `isStringSerializable`.

	See_Also: `vibe.data.serialization.serializeWithPolicy`
*/
template isPolicySerializable(alias Policy, T)
{
	enum bool isPolicySerializable = is(typeof(Policy!T.toRepresentation(T.init))) &&
		is(typeof(Policy!T.fromRepresentation(Policy!T.toRepresentation(T.init))) == T);
}

/**
	Chains serialization policy.

	Constructs a serialization policy that given a type `T` will apply the
	first compatible policy `toRepresentation` and `fromRepresentation`
	functions. Policies are evaluated left-to-right according to
	`isPolicySerializable`.

	See_Also: `vibe.data.serialization.serializeWithPolicy`
*/
template ChainedPolicy(alias Primary, Fallbacks...)
{
	static if (Fallbacks.length == 0) {
		alias ChainedPolicy = Primary;
	} else {
		alias ChainedPolicy = ChainedPolicy!(ChainedPolicyImpl!(Primary, Fallbacks[0]), Fallbacks[1..$]);
	}
}

private template ChainedPolicyImpl(alias Primary, alias Fallback)
{
	template Pol(T)
	{
		static if (isPolicySerializable!(Primary, T)) {
			alias toRepresentation = Primary!T.toRepresentation;
			alias fromRepresentation = Primary!T.fromRepresentation;
		} else {
			alias toRepresentation = Fallback!T.toRepresentation;
			alias fromRepresentation = Fallback!T.fromRepresentation;
		}
	}
	alias ChainedPolicyImpl = Pol;
}

private template isBuiltinTuple(T, string member)
{
    alias TM = AliasSeq!(typeof(__traits(getMember, T.init, member)));
    static if (TM.length > 1) enum isBuiltinTuple = true;
    else static if (is(typeof(__traits(getMember, T.init, member)) == TM[0]))
        enum isBuiltinTuple = false;
    else enum isBuiltinTuple = true; // single-element tuple
}

// heuristically determines @safe'ty of the serializer by testing readValue and writeValue for type int
private template isSafeSerializer(S)
{
	alias T = Traits!(int, DefaultPolicy);
	static if (__traits(hasMember, S, "writeValue"))
		enum isSafeSerializer = __traits(compiles, (S s) @safe { s.writeValue!T(42); });
	else static if (__traits(hasMember, S, "readValue"))
		enum isSafeSerializer = __traits(compiles, (S s) @safe { s.readValue!(T, int)(); });
	else static assert(0, "Serializer without writeValue or readValue is invalid");
}

private template hasAttribute(T, alias decl) { enum hasAttribute = findFirstUDA!(T, decl).found; }

private template hasPolicyAttribute(alias T, alias POLICY, alias decl)
{
	enum hasPolicyAttribute = hasAttribute!(T!POLICY, decl) || hasAttribute!(T!DefaultPolicy, decl);
}

private template hasAttributeL(T, ATTRIBUTES...) {
	static if (ATTRIBUTES.length == 1) {
		enum hasAttributeL = is(typeof(ATTRIBUTES[0]) == T);
	} else static if (ATTRIBUTES.length > 1) {
		enum hasAttributeL = hasAttributeL!(T, ATTRIBUTES[0 .. $/2]) || hasAttributeL!(T, ATTRIBUTES[$/2 .. $]);
	} else {
		enum hasAttributeL = false;
	}
}

private template hasPolicyAttributeL(alias T, alias POLICY, ATTRIBUTES...)
{
	enum hasPolicyAttributeL = hasAttributeL!(T!POLICY, ATTRIBUTES) || hasAttributeL!(T!DefaultPolicy, ATTRIBUTES);
}

private static T getAttribute(TT, string mname, T)(T default_value)
{
	enum val = findFirstUDA!(T, __traits(getMember, TT, mname));
	static if (val.found) return val.value;
	else return default_value;
}

private static auto getPolicyAttribute(TT, string mname, alias Attribute, alias Policy)(Attribute!DefaultPolicy default_value)
{
	enum val = findFirstUDA!(Attribute!Policy, TypeTuple!(__traits(getMember, TT, mname))[0]);
	static if (val.found) return val.value;
	else {
		enum val2 = findFirstUDA!(Attribute!DefaultPolicy, TypeTuple!(__traits(getMember, TT, mname))[0]);
		static if (val2.found) return val2.value;
		else return default_value;
	}
}

private string underscoreStrip(string field_name)
@safe nothrow @nogc {
	if( field_name.length < 1 || field_name[$-1] != '_' ) return field_name;
	else return field_name[0 .. $-1];
}


private template hasSerializableFields(T, alias POLICY, size_t idx = 0)
{
	enum hasSerializableFields = SerializableFields!(T, POLICY).length > 0;
	/*static if (idx < __traits(allMembers, T).length) {
		enum mname = __traits(allMembers, T)[idx];
		static if (!isRWPlainField!(T, mname) && !isRWField!(T, mname)) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else static if (hasAttribute!(IgnoreAttribute, __traits(getMember, T, mname))) enum hasSerializableFields = hasSerializableFields!(T, idx+1);
		else enum hasSerializableFields = true;
	} else enum hasSerializableFields = false;*/
}

private template hasDeserializableFields(T, alias POLICY, size_t idx = 0)
{
	enum hasDeserializableFields = DeserializableFields!(T, POLICY).length > 0;
}

private template SerializableFields(COMPOSITE, alias POLICY)
{
	alias SerializableFields = FilterSerializableFields!(true, COMPOSITE, POLICY, __traits(allMembers, COMPOSITE));
}

private template DeserializableFields(COMPOSITE, alias POLICY)
{
	alias DeserializableFields = FilterSerializableFields!(false, COMPOSITE, POLICY, __traits(allMembers, COMPOSITE));
}

private template FilterSerializableFields(bool toSerialize, COMPOSITE, alias POLICY, FIELDS...)
{
	static if (FIELDS.length > 1) {
		alias FilterSerializableFields = TypeTuple!(
			FilterSerializableFields!(toSerialize, COMPOSITE, POLICY, FIELDS[0 .. $/2]),
			FilterSerializableFields!(toSerialize, COMPOSITE, POLICY, FIELDS[$/2 .. $]));
	} else static if (FIELDS.length == 1) {
		alias T = COMPOSITE;
		enum mname = FIELDS[0];
		static if (isRWPlainField!(T, mname) || isRWField!(T, mname)) {
			alias Tup = TypeTuple!(__traits(getMember, COMPOSITE, FIELDS[0]));
			static if (Tup.length != 1) {
				alias FilterSerializableFields = TypeTuple!(mname);
			} else {
				enum ig = getPolicyAttribute!(T, mname, IgnoreAttribute, POLICY)(IgnoreAttribute!DefaultPolicy(IgnoreDirection.req)).direction;
				static if ((toSerialize && ((ig & IgnoreDirection.out_) != IgnoreDirection.out_))
					|| (!toSerialize && ((ig & IgnoreDirection.in_) != IgnoreDirection.in_)))
				{
					alias FilterSerializableFields = TypeTuple!(mname);
				} else alias FilterSerializableFields = TypeTuple!();
			}
		} else alias FilterSerializableFields = TypeTuple!();
	} else alias FilterSerializableFields = TypeTuple!();
}

private size_t getExpandedFieldCount(T, FIELDS...)()
{
	size_t ret = 0;
	foreach (F; FIELDS) ret += TypeTuple!(__traits(getMember, T, F)).length;
	return ret;
}

private template getExpandedFieldsData(T, FIELDS...)
{
	import std.meta : aliasSeqOf, staticMap;
	import std.range : repeat, zip, iota;

	enum subfieldsCount(alias F) = TypeTuple!(__traits(getMember, T, F)).length;
	alias processSubfield(alias F) = aliasSeqOf!(zip(repeat(F), iota(subfieldsCount!F)));
	alias getExpandedFieldsData = staticMap!(processSubfield, FIELDS);
}
