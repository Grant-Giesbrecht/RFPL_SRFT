classdef Netlist < handle

	properties

		components
		
		next_unique_id

		ref_ids
	end

	methods
		function obj = Netlist(comp)
			obj.components = comp;
			
			obj.next_unique_id = 1;
			
			obj.ref_ids = containers.Map();
		end

		function tf = addAt(obj, elmnt, idx)
		%
		% components = [A, B, C, D]
		% addTo(X, 3)
		% components = [A, B, X, C, D];
		%
			
			tf = true;
			
			% Verify that correct type is being added
			if ~isa(elmnt, 'CircElement')
				warning("Failed to add element. Incorrect type (expected CircElement)");
				tf = false;
				return;
			end

			% Assign a unique ID to the element
			elmnt.unique_id = obj.next_unique_id;
			obj.next_unique_id = obj.next_unique_id + 1;
			
			obj.components = [obj.components(1:idx-1), elmnt, obj.components(idx:end)];
			
		end
		
		function tf = add(obj, elmnt)

			obj.addAt(elmnt, length(obj.components)+1);
			
		end
		
		function idx = ID2Idx(obj, ID)
			
			index = 0;
			for e = obj.components
				
				index = index + 1;
				
				if e.unique_id == ID
					idx = index;
					return;
				end
				
			end
			
		end

		function tf = simplify(obj)
		%
		%
		%	* purge shorts
		%   * Combine parallel elements
		%	* Combine shunt elements
		%
		
			%TODO: Fix this so it works with any and all topologies, not
			%just ladder
			
			
			
			% Combine serial and parallel components until no more
			% simplifications can be mades
			modified = true;
			while modified
				
				% Combine parallel components
				modified = obj.pallCombine();
				
				% Combine serial components
				modified = modified || obj.serCombine();
				
			end
			
			
		
		end
		
		function mod = pallCombine(obj)
			
			del_idx = [];
			mod = false;
			
			% Combine parallel elements
			ei = 0;
			while ei < length(obj.components)-1 % Loop over each element
				
				% Increment counter
				ei = ei + 1;
				
				% Skip if first node does not match
				if obj.components(ei).nodes(1) ~= obj.components(ei+1).nodes(1)
					continue;
				end
				
				% Skip if 2nd node does not match
				if obj.components(ei).nodes(2) ~= obj.components(ei+1).nodes(2)
					continue;
				end
				
				% Skip if not same type of component
				if ~strcmp(obj.components(ei).ref_type, obj.components(ei+1).ref_type)
					continue;
				end
				
				% Combine elements
				if strcmp(obj.components(ei).ref_type, "C")
					obj.components(ei).val = obj.components(ei).val + obj.components(ei+1).val;
				elseif strcmp(obj.components(ei).ref_type, "L") || strcmp(obj.components(ei).ref_type, "R")
					obj.components(ei).val = pall( obj.components(ei).val, obj.components(ei+1).val);
				else
					continue;
				end
				
				mod = true;
				
				% Mark second for deletion
				del_idx = addTo(del_idx, ei+1);
				
				% Increment counter again if elements combined
				ei = ei + 1;
			end
			
			% Delete combined components
			obj.components(del_idx) = [];
			
		end
		
		function mod = serCombine(obj)
			
			del_idx = [];
			mod = false;
			
			% Combine series elements
			ei = 0;
			while ei < length(obj.components)-1 % Loop over each element
				
				% Increment counter
				ei = ei + 1;
				
				% Skip if elements dont share any nodes
				if ~isSeries(obj.components(ei), obj.components(ei+1))
					continue;
				end
				
				% Skip if not same type of component
				if ~strcmp(obj.components(ei).ref_type, obj.components(ei+1).ref_type)
					continue;
				end
				
				% Combine elements
				if strcmp(obj.components(ei).ref_type, "C")
					obj.components(ei).val = pall( obj.components(ei).val, obj.components(ei+1).val);
				elseif strcmp(obj.components(ei).ref_type, "L") || strcmp(obj.components(ei).ref_type, "R")
					obj.components(ei).val = obj.components(ei).val + obj.components(ei+1).val;
				else
					continue;
				end
				
				mod = true;
				
				% Mark second for deletion
				del_idx = addTo(del_idx, ei+1);
				
				% Increment counter again if elements combined
				ei = ei + 1;
			end
			
			% Delete combined components
			obj.components(del_idx) = [];
		end
		
		function purge(obj, varargin)

			%TODO: Fix how this works when not just ladder, removing
			%elements should instead replace them with short, later
			%simplify short by removing parallel, renaming, etc.

			p = inputParser;
			p.addParameter('Zopen', 100e6, @isnumeric);
			p.addParameter('Zshort', 1e-3, @isnumeric);
			p.addParameter('f_low', 1e6, @isnumeric);
			p.addParameter('f_high', 1e9, @isnumeric);
			p.parse(varargin{:});

			Z_open = p.Results.Zopen;
			Z_short = p.Results.Zshort;
			freqs = [p.Results.f_low, p.Results.f_high];

			% Scan over all elements
			pop_idx = []; % Indeces of elements to delete
			replacements = []; %Node to rename with other
			idx = 0;
			for elmt=obj.components
				idx = idx + 1;

				% Get impedances at all test points
					Zs = abs(elmt.Z(freqs));

				if strcmp(elmt.nodes(2), "GND") %If is an admittance...

					% If element is open at all points, delete
					if all( Zs > Z_open)
						pop_idx = addTo(pop_idx, idx);

						% If brides two nodes, add to replacement list
						if numel(elmt.nodes) > 1
							s = struct('fnd', elmt.nodes(2:end), 'rep', elmt.nodes(1));
							replacements = addTo(replacements, s);
						end
					end

				else % Else if an impedance

					% If element is shorted at all points, delete
					if all( Zs < Z_short)
						pop_idx = addTo(pop_idx, idx);

						% If brides two nodes, add to replacement list
						if numel(elmt.nodes) > 1
							idx = 2;
							for idx = 2:numel(elmt.nodes) % Loop over all nodes (if more than 2 present)
								s = struct('fnd', elmt.nodes(idx), 'rep', elmt.nodes(1));
								replacements = addTo(replacements, s);
							end

						end

					end

				end

			end

			% Delete marked elements
			obj.components(pop_idx) = [];

			%Rename replaced nodes
			for elmt = obj.components % For each element

				% Check each find/replacement pair
				for r = replacements

					% Scan over all nodes
					for ni = 1:length(elmt.nodes)

						% If nodes match
						if strcmp(elmt.nodes(ni), r.fnd)

							% Replace with replacement value
							elmt.nodes(ni) = r.rep;
						end

					end

				end
			end

		end
		
		function annotate(obj, reset)
			
			% Check if 'reset' exists
			if ~exist('reset', 'var')
				reset = false;
			end
			
			% Reset annotations if asked
			if reset
				for c=obj.components
					c.ref_num = 0;
				end
			end
			
			% For each component...
			for c=obj.components
				
				% Skip labeled components
				if c.ref_num ~= 0
					continue;
				end
				
				% Otherwise check if key exists
				if isKey(obj.ref_ids, c.ref_type)
					
					% Get new ID
					c.ref_num = Netlist.nextListID(obj.ref_ids(c.ref_type));
					
					% Add ID to list
					obj.ref_ids(c.ref_type) = addTo(obj.ref_ids(c.ref_type), c.ref_num);
				else
					
					% Assign component as '1'
					c.ref_num = 1;
					
					% Add to ref_ids
					obj.ref_ids(c.ref_type) = 1;
				end
				
			end
			
		end %========================= END annotate() =====================

		function s = str(obj, indent)

			simple_output = false;
			precision = 3;
			
			if ~exist('indent', 'var')
				indent = "    ";
			end

			s = "";

			if simple_output
				% Display result
				for c=obj.components

					% Add newline after each line
					if ~strcmp(s, "")
						s = s + newline;
					end

					s = strcat(s, indent, c.str());

				end
			else
				
				obj.annotate();
				
				% Initialize table
				mt = MTable();
				mt.table_title("Netlist");
				mt.row(["Ref.", "Value", "Node 1", "Node 2", "Z0", "Stub Type"]);
				
				rowstr = "";
				
				for c=obj.components
					
					rowstr = strcat(c.ref_type, string(c.ref_num));
					rowstr(2) = strcat(MTable.prd(c.val, precision), " ", c.val_unit);
					rowstr(3) = c.nodes(1);
					rowstr(4) = c.nodes(2);
					rowstr(5) = " - ";
					rowstr(6) = " - ";
					
					% Handle TL specific fields
					if c.ref_type == "TL"
						if isKey(c.props, "Z0")
							if isnumeric(c.props("Z0"))
								rowstr(5) = MTable.prd(c.props("Z0"), 1);
							else
								rowstr(5) = c.props("Z0");
							end
						end
						if isKey(c.props, "Stub")
							if c.props("Stub") && isKey(c.props, "TERM")
								rowstr(6) = "Stub: " + c.props("TERM");
							else
								rowstr(6) = "TLine";
							end
						end
					end
					
					mt.row(rowstr);
					
				end
				
				mt.alignac('r');
				
				s = mt.str();
				
			end
			
			
		end

	end
	
	methods (Static)
		
		function id = nextListID(list, quick)
			
			if ~exist('quick', 'var')
				quick = false;
			end
			
			% Make sure list is numeric
			if ~isnumeric(list)
				id = NaN;
				return;
			end
			
			if ~quick
				id = 1;
				while any(id == list)
					id = id + 1;
				end
			else
				id = ceil(max(list))+1;
			end
		end
		
	end

end
