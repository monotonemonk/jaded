module jade.base;

import std.stdio;
import std.file;
import std.array : replicate;

import jade.pegged;

import std.conv : to;

string render(alias filename)() {
	pragma(msg, "compile time:");
	enum templ = import(filename);
	enum tmp = blockWrapJadeFile(templ);
	pragma(msg, "===============================================================================");
	//return tmp;
	enum parse_tree = Jade(tmp);
	//enum tmp2 = jadeToTree(parse_tree);
	//printParseTree(tmp2);
	enum result = renderParseTree(filename, parse_tree); // Should we use a different readParseTree function here? This is the last place I currently use enum...
	return result;
}

void render(T)(T output_stream, string filename) {
	auto templ = readText("views/"~filename);
	auto tmp = blockWrapJadeFile(templ);
	auto parse_tree = Jade(tmp);
	//writeln("tree\n", parse_tree);
	//auto tmp2 = jadeToTree(parse_tree);
	//output_stream.write(tmp2);
	auto result = renderParseTree(filename, parse_tree);
	////auto result = "%s".format(parse_tree);
	output_stream.write(result);
}

import pegged.parser;
import std.string : format;
string renderParseTree(string filename, ParseTree p) {
	auto parser = new JadeParser(filename, p);
	return parser.render();
}

import std.array;
struct JadeParser {
	string name;
	this(string filename, ParseTree p) {
		import std.string : indexOf;
		this.name = filename[0..filename.indexOf(".")];
		//writeln(this);
		this.ranges ~= LineRange(p.children, 0);
	}
	LineRange[] ranges;
	LineRange range() {
		return ranges[$-1];
	}
	class Item {
		int depth;
		ParseTree p;
		string prolog, epilog;
		Item[] items;
		alias p this;
		this(int depth, ParseTree p) {
			this.depth = depth;
			this.p = p;
		}
		override
		string toString() {
			auto ret = appender!string;
			//ret ~= "writeln(`%s<!-- %s:%s -->`);\n".format("\t".replicate(depth), p.name, p.matches.length > 0 ? p.matches[0] : "");
			ret ~= "writeln(`%s<!-- %s:%s -->`);\n".format("\t".replicate(depth), p.name, p.matches.length > 3 ? p.matches[0..3] : p.matches[0..$]);
			//return "%s".format(p.name);
			ret ~= prolog;
			foreach (item; items) {
				if (item.name == "Jade.PipedText") {
					ret ~= "writeln(`%s`);".format(item.matches[0]);
				} else {
					ret ~= item.toString();
				}
			}
			ret ~= epilog;
			return ret.data;
		}
	}
	struct LineRange {
		@disable this();
		this(ParseTree[] lines, int min_depth) {
			this.lines = lines;
			this.index = 0;
			this.min_depth = min_depth;
			skip();
		}
		ParseTree[] lines;
		int min_depth;
		size_t index = 0;
		Item front() {
			ulong depth;
			if (lines[index].name == "Jade.Line" && lines[index].children.length > 0 && lines[index].children[0].name == "Jade.Indent") {
				depth = lines[index].children[0].matches[0].length;
				return new Item(cast(int)depth, lines[index].children[1].children[0]);
			} else if (lines[index].name == "Jade.Line") {
				return new Item(cast(int)depth, lines[index].children.length > 0 ? lines[index].children[0] : lines[index]);
			} else {
				depth = 0;
				return new Item(cast(int)depth, lines[index]);
			}
			//return Line(cast(int)depth, lines[index]);
		}
		void popFront()
		in {
			assert(index <= lines.length);
		}
		body {
			// move forward, past all indented lines
			index++;
			skip();
		}
		bool empty() {
			return index >= lines.length || front.depth < min_depth;
		}
		private void skip() {
			while (!empty && lines[index].name == "Jade.Line" && lines[index].matches.length == 1 && lines[index].matches[0] == "\n") {
				index++;
			}
		}
	}
	/** Entry point for render*/
	string render() {
		string ret;
		//ret ~= "writeln(`render:%s%s`);".format("\t".replicate(stop_depth+1), range.lines.length);
		//if (!range.empty)
		//	ret ~= "writeln(`range empty? %s - %s vs %s vs %s - %s || %s -- %s`);".format(range.empty, range.front.depth, range.min_depth ? range.min_depth : stop_depth, range.index, range.index >= range.lines.length, range.front.depth < range.min_depth, range.lines.length > range.index ? range.front.name : "empty for real");
		while (!range.empty) {
			auto item = renderTag(range.front);
			ret ~= "%s".format(item);
		}
		return ret;
	}
	/** Used by renderTag for rendering recursively */
	private Item[] render(int stop_depth) {
		Item[] ret;
		//ret ~= "writeln(`render:%s%s`);".format("\t".replicate(stop_depth+1), range.lines.length);
		//if (!range.empty)
		//	ret ~= "writeln(`range empty? %s - %s vs %s vs %s - %s || %s -- %s`);".format(range.empty, range.front.depth, range.min_depth ? range.min_depth : stop_depth, range.index, range.index >= range.lines.length, range.front.depth < range.min_depth, range.lines.length > range.index ? range.front.name : "empty for real");
		while (!range.empty) {
		//ret ~= "writeln(`\t empty? %s - %s vs %s vs %s - %s || %s -- %s`);".format(range.empty, range.front.depth, range.min_depth ? range.min_depth : stop_depth, range.index, range.index >= range.lines.length, range.front.depth < range.min_depth, range.lines.length > range.index ? range.front.name : "empty for real");
			if (stop_depth >= 0 && range.front.depth <= stop_depth) break;
			//ret ~= "writeln(`range not empty`);";
			ret ~= renderTag(range.front);
		}
		return ret;
	}
	private Item renderTag(Item token) {
		switch (token.name) {
			case "Jade.RootTag":
				token.prolog ~= "writeln(`<!-- jade template: %s.jade %s-->`);".format(name, token.children.length);
				ranges ~= LineRange(token.children, token.depth);
				token.prolog ~= render();
				ranges.popBack();
				range.popFront();
				break;
			case "Jade.Extend":
				token.prolog ~= "pragma(msg, render!`%s`); mixin(render!`%s`);".format(token.matches[1], token.matches[1]);
				range.popFront();
				break;
			case "Jade.Include":
				token.prolog ~= "writeln(import(`%s`));".format(token.matches[0]);
				range.popFront();
				break;
			case "Jade.Block":
				token.prolog ~= "writeln(`<block>`);";
				//token.prolog ~= "writeln(`<!-- %s %s depth:%s -->` \"\n\" `block`);".format(ranges.length, token.name, token.depth);
				range.popFront();
				token.items = render(token.depth);
				token.epilog ~= "writeln(`</block>`);";
				break;
			case "Jade.Tag":
				range.popFront();
				auto hasChildren = !range.empty && range.front.depth > token.depth;
				auto name = token.matches[0];
				if (name==".") {
					name = "div";
				}
				if (!hasChildren) {
					if (name=="img") {
						token.prolog ~= "writeln(`%s<%s />`);".format("\t".replicate(token.depth), name);
					} else {
						token.prolog ~= "writeln(`%s<%s></%s>`);".format("\t".replicate(token.depth), name, name);
					}
				} else {
					assert(name != "img", "<img /> tag cannot have children");
					token.prolog ~= "writeln(`%s<%s>`);".format("\t".replicate(token.depth), name);
					//token.prolog ~= "writeln(`<!-- %s %s depth:%s -->` `tag:%s`);".format(ranges.length, token.name, token.depth, token.matches[0]);
					token.items = render(token.depth);
					token.epilog ~= "writeln(`%s</%s>`);".format("\t".replicate(token.depth), name);
				}
				break;
			case "Jade.PipedText":
				token.prolog ~= "writeln(`<!-- %s %s depth:%s -->` `PipedText:%s`);".format(ranges.length, token.name, token.depth, token.matches);
				range.popFront();
				break;
			case "Jade.Line":
			default:
				token.prolog ~= "writeln(`<!-- %s %s depth:%s -->`);".format(ranges.length, token.name, token.depth);
				range.popFront();
		}
		return token;
	}
}

bool isIndentedLine(ParseTree p) {
	if (p.children.length < 1 || p.name != "Jade.Line" || p.children[0].name != "Jade.Indent" || p.children[1].name != "Jade.Line") {
		return false;
	}
	if (p.matches.length > 0 && p.children.length > 0 && p.matches[0][0]=='\t') {
		return true;
	}
	return false;
}

ParseTree* findParseTree(ref ParseTree p, string name, int maxDepth=int.min) {
	if (maxDepth != int.min && maxDepth < 0) return null;
	if (p.name == name) {
		return &p;
	}
	foreach (child; p.children) {
		auto tmp = findParseTree(child, name, maxDepth-1);
		if (tmp !is null) {
			return tmp;
		}
	}
	return null;
}





/**
 * Pre-process jade file, making pegged parser capable of understanding indented BlockInATag blocks
 */
string blockWrapJadeFile(string templ) {
	import std.conv;
	import std.algorithm : countUntil;
	import std.array;
	import std.string : split, strip, lineSplitter;
	auto buf = appender!string;
	buf.reserve(templ.length*2);

	long last_indent;
	long raw_indent;
	bool isRawBlock;
	foreach (line; templ.lineSplitter) {
		if (line == "}") throw new Exception("Unexpected } on line by itself"); // protect against accidental use of our special marker
		auto indent = line.countUntil!"a != 0x09";
		auto strippedLine = line.strip;
		indent = indent < 0 ? 0 : indent;

		//buf ~= to!string(indent);
		if (line.length>0 && strippedLine[$-1]=='.' && indent <= raw_indent) {
			if (isRawBlock) buf ~= "}\n"; // if a raw block tag follows a raw block tag

			buf ~= line;
			buf ~= '{';
			isRawBlock = true;
			raw_indent = indent;
		} else if (isRawBlock && indent <= raw_indent) {
			buf ~= "}\n";
			isRawBlock = false;
			buf ~= line;
		} else {
			buf ~= line;
		}
		buf ~= '\n';
		last_indent = indent;
	}

	return buf.data;
}
//Node jadeToTree(ref ParseTree p) {
//	size_t index;
//	auto ret = Node(p.children[0].name);
//	jadeToTreeWorker(ret, p.children[0].children, index);
//	writeln("ret: ", ret);
//	return ret;
//}
//struct Node {
//	string name;
//	string[] matches;
//	Node[] children;
//}
//void jadeToTreeWorker(ref Node parent, ParseTree[] lines, ref size_t index, int parent_depth = -1) {
//	writeln(">>>>");
//	while (index < lines.length-1) {
//		auto current = lines[index];
//		auto depth = cast(int)(current.matches.length > 0 && current.matches[0].length > 0 && current.matches[0][0] == '\t' ? current.matches[0].length : 0);
//		if (depth <= parent_depth) {
//			return;
//		}
//		parent.children ~= Node(current.name, current.matches[0.. $ > 2 ? 2 : $]);
//		jadeToTreeWorker(parent.children[$-1], lines[index+1..$], index, depth);
//		index++;
//	}
//	//writeln("p::", ret);
//}
