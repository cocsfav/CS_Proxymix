/***
* Name: COVID
* Author: admin_ptaillandie
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model COVID

global {
	
	file ML_file <- dxf_file("../includes/Standard_Factory_Gama.dxf",#cm);
	shape_file pedestrian_path_shape_file <- shape_file("../includes/pedestrian_path.shp");
	date starting_date <- date([2020,4,6,7]);
	int nb_people <- 300;
	geometry shape <- envelope(ML_file);
	graph pedestrian_network;
	map<string,rgb> standard_color_per_type <- 
	["Offices"::#blue,"Meeting rooms"::#darkblue,
	"Entrance"::#yellow,"Elevators"::#orange,
	"Coffee"::#green,"Supermarket"::#darkgreen,
	"Storage"::#brown, "Furnitures"::#maroon, 
	"Toilets"::#purple, "Toilets_Details"::#magenta, 
	"Walls"::#gray, "Doors"::#lightgray,
	"Stairs"::#white,"Path"::#red];
	list<room> available_offices;
	list<room> entrances;
	init {
		create pedestrian_path from: pedestrian_path_shape_file;
		pedestrian_network <- as_edge_graph(pedestrian_path);
		loop se over: ML_file {
			string type <- se get "layer";
			if (type = "Walls") {
				create wall with: [shape::polygon(se.points)];
			} else if type = "Entrance" {
				create building_entrance  with: [shape::polygon(se.points), type::type] {
					do intialization;
				}
			} else if type in ["Offices", "Supermarket", "Meeting rooms","Coffee","Storage"] {
				create room with: [shape::polygon(se.points), type::type] {
					do intialization;
					
				}
				
			}
		} 
		ask room {
			list<wall> ws <- wall overlapping self;
			loop w over: ws {
				if w covers self {
					do die;
				}
			}
		}
		ask room + building_entrance{
			geometry contour <- shape.contour;
			ask wall at_distance 1.0 {
				contour <- contour - (shape + 0.3);
			}
			ask (room + building_entrance) at_distance 1.0 {
				contour <- contour - (shape + 0.3);
			} 
			if contour != nil {
				entrances <- points_on (contour, 2.0);
			}
			ask places {
				point pte <- myself.entrances closest_to self;
				dists <- self distance_to pte;
			}
					
		}
		map<string, list<room>> rooms_type <- room group_by each.type;
		entrances <-list(building_entrance);
		loop ty over: rooms_type.keys  - ["Offices", "Entrance"]{
			create activity {
				name <-  ty;
				activity_places <- rooms_type[ty];
			}
		}
		create working;
		create going_home with:[activity_places:: entrances];
		
		available_offices <- rooms_type["Offices"] where each.is_available();
	}	
	
	
	
	action create_people(int nb) {
		create people number: nb {
			working_place <- one_of (available_offices);
			working_place.nb_affected <- working_place.nb_affected + 1;
			if not(working_place.is_available()) {
				available_offices >> working_place;
			}
			current_activity <- first(working);
			target_room <- current_activity.get_place(self);
			target <- target_room.entrances closest_to self;
			
			goto_entrance <- true;
			location <- any_location_in (one_of(entrances));
			date lunch_time <- date(current_date.year,current_date.month,current_date.day,11, 30) add_seconds rnd(0, 40 #mn);
			
			if flip(0.3) {agenda_day[lunch_time] <- activity first_with (each.name = "Supermarket");}
			lunch_time <- lunch_time add_seconds rnd(120, 10 #mn);
			agenda_day[lunch_time] <- activity first_with (each.name = "Coffee");
			lunch_time <- lunch_time add_seconds rnd(5#mn, 30 #mn);
			agenda_day[lunch_time] <- first(working);
			agenda_day[date(current_date.year,current_date.month,current_date.day,18, rnd(30),rnd(59))] <- first(going_home);
			
		}
		
	}
	
	reflex change_step {
		if (current_date.hour >= 7 and current_date.minute > 10 and empty(people where (each.target != nil)))  {
			
			step <- 5#mn;
		}
		if (current_date.hour = 11 and current_date.minute > 30){
			step <- 1#s;
		}
		if (current_date.hour >= 12 and current_date.minute > 5 and empty(people where (each.target != nil)))  {
			step <- 5 #mn;
		} 
		if (current_date.hour = 18){
			step <- 1#s;
		}
		if (not empty(people where (each.target != nil))) {
			step <- 1#s;
		}
	}
	
	reflex end_simulation when: after(starting_date add_hours 13) {
		do pause;
	}
	
	reflex people_arriving when: not empty(available_offices) 
	{
		do create_people(rnd(0,min(5, length(available_offices))));
	}
}

species pedestrian_path;

species wall {
	aspect default {
		draw shape color: #gray;
	}
}

species room {
	int nb_affected;
	string type;
	list<point> entrances;
	list<place_in_room> places;
	list<place_in_room> available_places;
	
	action intialization {
		loop g over: to_squares(shape, 1.5, true) where (each.location overlaps shape){
						create place_in_room {
							location <- g.location;
							myself.places << self;
						}
					} 
					if empty(places) {
						create place_in_room {
							location <- myself.location;
							myself.places << self;
						}
					} 
				
					available_places <- copy(places);
	}
	bool is_available {
		return nb_affected < length(places);
	}
	place_in_room get_target(people p){
		place_in_room place <- (available_places with_max_of each.dists);
		available_places >> place;
		return place;
	}
	
	aspect default {
		draw shape color: standard_color_per_type[type];
		loop e over: entrances {draw square(0.1) at: e color: #magenta border: #black;}
		loop p over: available_places {draw square(0.1) at: p.location color: #cyan border: #black;}
	}
}

species building_entrance parent: room {
	place_in_room get_target(people p){
		return place_in_room closest_to p;
	}
}

species activity {
	list<room> activity_places;
	
	room get_place(people p) {
		if flip(0.3) {
			return one_of(activity_places with_max_of length(each.available_places));
		} else {
			return (activity_places where not empty(each.available_places)) closest_to p;
		}
		
	}
	
}

species working parent: activity {
	
	room get_place(people p) {
		return p.working_place;
	}
}

species going_home parent: activity  {
	string name <- "going home";
	room get_place(people p) {
		return building_entrance closest_to p;
	}
}

species place_in_room {
	float dists;
}

species people skills: [moving] {
	room working_place;
	map<date, activity> agenda_day;
	activity current_activity;
	point target;
	room target_room;
	bool has_place <- false;
	place_in_room target_place;
	bool goto_entrance <- false;
	bool go_oustide_room <- false;
	rgb color <- rnd_color(255);
	float speed <- min(2,gauss(4,1)) #km/#h;
	aspect default {
		draw circle(0.3) color:color border: #black;
	}
	reflex define_activity when: not empty(agenda_day) and 
		(after(agenda_day.keys[0])){
		if(target_place != nil and (has_place) ) {target_room.available_places << target_place;}
		current_activity <- agenda_day.values[0];
		agenda_day >> first(agenda_day);
		target <- target_room.entrances closest_to self;
		target_room <- current_activity.get_place(self);
		go_oustide_room <- true;
		goto_entrance <- false;
		target_place <- nil;
	}
	
	reflex goto_activity when: target != nil{
		if goto_entrance {do goto target: target on: pedestrian_network;}
		else {do goto target: target; }
		if(location = target) {
			if (go_oustide_room) {
				target <- target_room.entrances closest_to self;
				go_oustide_room <- false;
				goto_entrance <- true;
			}
			else if (goto_entrance) {
				target_place <- target_room.get_target(self);
				if target_place != nil {
					target <- target_place.location;
					goto_entrance <- false;
				} else {
					room tr <- current_activity.get_place(self);
					if (tr != nil ) {
						target_room <- tr;
						target <- target_room.entrances closest_to self;
					}
				}
			} else {
				has_place <- true;
				target <- nil;
				if (current_activity.name = "going home") {
					do die;
				}
			}	
		}
 	}
}



experiment COVID type: gui {
	output {
		display map synchronized: true {
			species room;
			species building_entrance;
			species wall;
			species people;
		}
	}
}
