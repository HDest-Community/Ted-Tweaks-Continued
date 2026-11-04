// ------------------------------------------------------------
// All damage that affects the player goes here.
// ------------------------------------------------------------
extend class HDPlayerPawn{
	int inpain;
	override int DamageMobj(
		actor inflictor,
		actor source,
		int damage,
		name mod,
		int flags,
		double angle
	){
		//"You have to be aware of recursively called code pointers in death states.
		//It can easily happen that Actor A dies, calling function B in its death state,
		//which in turn nukes the data which is being checked in DamageMobj."
		if(!self || health<1)return damage;

		//don't do all this for...
		if(
			!player  //voodoo dolls
			||(
				//E1M8 end-level damage
				mod=="None"
				&&!inflictor
				&&!source
			)
		){
			if(player)AddBlackout(128,damage+16,16);
			return super.DamageMobj(inflictor,source,damage,mod,flags,angle);
		}

		int originaldamage=damage;

		silentdeath=false;

		//replace all armour with custom HD stuff
		if(countinv("PowerIronFeet")){
			A_GiveInventory("WornRadsuit");
			A_TakeInventory("PowerIronFeet");
		}
		if(countinv("BasicArmor")){
			A_GiveInventory("GarrisonArmourWorn");
			A_TakeInventory("BasicArmor");
		}

		if(
			damage==TELEFRAG_DAMAGE
			&&source
		){
			if(source==self){
				flags|=DMG_FORCED;
			}

			//because spawn telefrags are bullshit
			else if(
				(
					(
						source.player
						&&source.player.mo==source
						&&self.player
						&&self.player.mo==self
					)||botbot(source)
				)&&(
					!deathmatch
					||level.time<TICRATE
					||source.getage()<10
				)
			){
				return -1;
			}
		}


		double towound=0;
		double wwidth=1.;
		int toburn=0;
		int tostun=0;
		int tobreak=0;
		int toaggravate=0;


		if(inflictor&&inflictor.bpiercearmor)flags|=DMG_NO_ARMOR;


		//deal with some synonyms
		HDMath.ProcessSynonyms(mod);


		//factor in cheats and server settings
		if(
			!(flags&DMG_FORCED)
			&&damage!=TELEFRAG_DAMAGE
		){
			if(
				binvulnerable||!bshootable
				||(player&&(
					player.cheats&(CF_GODMODE2|CF_GODMODE)
				))
			){
				A_TakeInventory("Heat");
				burncount=0;
				aggravateddamage=0;
				oldwoundcount=0;
				return 0;
			}
			double dfl=damage*hd_damagefactor;
			damage=int(dfl);
			if(frandom(0,1)<dfl-damage)damage++;
		}

		//credit and blame where it's due
		if(source is "BotBot")source=source.master;

		//abort if zero team damage, otherwise save factor for wounds and burns
		double tmd=1.;
		if(
			source is "PlayerPawn"
			&&source!=self
			&&isteammate(source)
			&&player!=source.player
		){
			if(teamdamage<=0) return 0;
			else tmd=teamdamage;
		}

		if(source&&source.player)flags|=DMG_PLAYERATTACK;


		if(
			mod=="crush"
		){
			//duck under crushing ceilings
			if(ceilingz<pos.z+height)player.crouching=-1;

			//Doom's crushing damage never made sense. I give up.
			//Punish the player with nothing more than an annoying delay.
			if(!inflictor&&!source)return -1;
		}


		//process all items (e.g. armour) that may affect the damage
		array<HDDamageHandler> handlers;
		if(
			!(flags&DMG_FORCED)
			&&damage<TELEFRAG_DAMAGE
		){
			HDDamageHandler.GetHandlers(self,handlers);
			for(int i=0;i<handlers.Size();i++){
				let hhh=handlers[i];
				if(hhh&&hhh.owner==self)
				[damage,mod,flags,towound,toburn,tostun,tobreak]=hhh.HandleDamage(
					damage,
					mod,
					flags,
					inflictor,
					source,
					towound,
					toburn,
					tostun,
					tobreak
				);
			}
		}


		//excess hp
		if(mod=="maxhpdrain"){
			damage=min(health-1,damage);
			flags|=DMG_NO_PAIN|DMG_THRUSTLESS;
		}
		//bleeding
		else if(
			mod=="bleedout"
			||mod=="internal"
		){
			flags|=(DMG_NO_ARMOR|DMG_NO_PAIN|DMG_THRUSTLESS);
			silentdeath=true;

			damage=min(health,damage);
			if(!random(0,127))oldwoundcount++;

			bool actuallybleeding=(mod!="internal");
			if(actuallybleeding){
				bloodloss+=(originaldamage<<2);

				if(level.time&(1|2))return -1;
				if(bloodloss<HDCONST_MAXBLOODLOSS){
					if(!(flags&DMG_FORCED))damage=clamp(damage>>2,1,health-1);
					if(!random(0,health)){
						beatcap--;
						if(!(level.time%4))bloodpressure--;
					}
				}
				if(damage<health)source=null;
			}
		}else if(
			mod=="hot"
			||mod=="cold"
		){
			//burned
			if(damage<=1){
				if(!random(0,27))toburn++;
				if(!random(0,95)){
					towound+=frandom(0,1);
					wwidth+=frandom(0,4);
				}
			}else{
				toburn+=int(max(damage*frandom(0.1,0.6),random(0,1)));
				if(!random(0,60)){
					towound+=max(1,0.03*damage);
					wwidth+=frandom(-0.2,0.4);
				}
			}
		}else if(
			mod=="electrical"
		){
			//electrocuted
			toburn+=int(max(damage*frandom(0.2,0.5),random(0,1)));
			if(!random(0,35)){
				towound+=1.;
				wwidth+=max(1,(damage>>4));
			}
			if(!random(0,1))tostun+=damage;
		}else if(
			mod=="balefire"
		){
			//balefired
			toburn+=int(damage*frandom(0.6,1.1));
			if(!random(0,2)){
				towound+=frandom(1,2);
				wwidth+=max(1,damage>>4);
			}
			if(random(1,50)<damage*tmd)toaggravate++;
			if(!(level.time&(1|2|4|8)))A_AlertMonsters();
		}else if(
			mod=="teeth"
			||mod=="claws"
			||mod=="natural"
		){
			if(!random(0,mod=="teeth"?12:36))toaggravate++;
			if(random(1,15)<damage){
				towound+=frandom(0.3,1.);
				wwidth+=frandom(0,2);
			}
			tostun+=int(damage*frandom(0,0.6));
		}else if(
			mod=="GhostSquadAttack"
		){
			//do nothing here, rely on TalismanGhost.A_GhostShot
		}else if(
			mod=="staples"
			||mod=="falling"
			||mod=="drowning"
			||mod=="slime"
		){
			//noarmour
			flags|=DMG_NO_ARMOR;

			if(mod=="falling"){
				if(!source)return -1; //ignore regular fall damage
				tostun+=damage*random(8,12);
				damage>>=1;
			}
			else if(mod=="slime"&&!random(0,127-damage))toaggravate++;
			else if(mod=="staples"&&!random(0,255))oldwoundcount++;
		}else if(
			mod=="slashing"
		){
			//swords, chainsaw, etc.
			if(!random(0,15)){
				towound+=max(1,0.04*damage);
				wwidth+=max(1,0.03*damage);
			}
		}else if(mod=="bashing"){
			tostun+=damage;
			damage>>=2;
		}else{
			//anything else
			if(!random(0,15)){
				towound+=max(1,0.03*damage);
				wwidth+=frandom(0,1);
			}
		}



		//abort if damage is less than zero
		if(damage<=0)return damage;



		//do more insidious damage from blunt impacts
		if(
			mod=="falling"
			||mod=="bashing"
		){
			int owc=random(1,100);
			if(owc<damage){
				int agg=(random(-owc,owc)>>3);
				if(agg>0){
					owc-=agg;
					toaggravate+=agg;
				}
				tobreak+=owc;
			}
		}



		//process all items that may affect damage after all the above
		if(
			!(flags&DMG_FORCED)
			&&damage<TELEFRAG_DAMAGE
		){
			HDDamageHandler.GetHandlers(self,handlers);
			for(int i=0;i<handlers.Size();i++){
				let hhh=handlers[i];
				if(hhh&&hhh.owner==self)
				[damage,mod,flags,towound,toburn,tostun,tobreak,toaggravate]=hhh.HandleDamagePost(
					damage,
					mod,
					flags,
					inflictor,
					source,
					towound,
					toburn,
					tostun,
					tobreak,
					toaggravate
				);
			}
		}



		//add to wounds and burns after team damage multiplier
		//(super.damagemobj() takes care of the actual damage amount)
		towound=towound*tmd;
		toburn=int(toburn*tmd);
		if(
			towound>0
			&&(
				!inflictor
				||!inflictor.bstoprails
			)
		){
			lastthingthatwoundedyou=source;
			hdbleedingwound.inflict(self,towound,wwidth,source:source,damagetype:mod,
				hitlocation:!!inflictor?inflictor.pos:!!source?source.pos+HDMath.GetGunPos(source):(0,0,0)
			);
		}
		if(toburn>0)burncount+=toburn;
		if(tostun>0)stunned+=tostun;
		if(tobreak>0)oldwoundcount+=tobreak;
		if(toaggravate>0)aggravateddamage+=toaggravate;

		//stun the player randomly
		if(
			damage>60
			||(
				!random(0,5)
				&&damage>20
			)
		){
			tostun+=damage;
		}

		if(hd_debug&&player){
			string st="the world";
			string src="";
			if(inflictor)st=inflictor.getclassname();
			if(source)src="("..source.getclassname()..")";
			A_Log(string.format("%s took %d %s damage from %s",
				player.getusername(),
				damage,
				mod,
				st
			));
		}



		//flinch
		if(
			!(flags&DMG_NO_PAIN)
			&&damage>0
			&&health>0
		){
			bool bash=mod=="bashing";
			double jerkamt=
				(
					(
						bash
						||mod=="melee"
					)
					&&source
					&&(
						source.bismonster
						||source.player
					)&&(
						source==inflictor
						||!inflictor
					)
				)?min(damage*(2.-strength)*3.,30.*hd_flinchmultiplier)
				:(
					mod=="electrical"
					||(
						bash
						&&!hdbulletactor(inflictor)
					)
				)?4.-strength
				:(
					mod=="hot"
					||mod=="cold"
					||mod=="balefire"
				)?3.
				:(
					mod=="claws"
					||mod=="teeth"
					||mod=="slashing"
				)?1.+damage*0.3*hd_flinchmultiplier
				:1.5
			;
			if(jerkamt<10)jerkamt/=max(1,bloodpressure>>2);
			let iii=inflictor;if(!iii)iii=source;
			double jerkleft=0;
			double jerkdown=0;
			if(iii){
				double aaaa=deltaangle(self.angle,angleto(iii));
				if(aaaa>1)jerkleft=jerkamt;
				else if(aaaa<-1)jerkleft=-jerkamt;

				double zzzz=(iii.pos.z+iii.height*0.5)-(pos.z+height*0.9);
				if(abs(zzzz)>10){
					if(zzzz<0)jerkdown=jerkamt;
					else jerkdown=-jerkamt;
				}
			}
			if(!jerkleft)jerkleft=frandom(-jerkamt,jerkamt);
			if(!jerkdown)jerkdown=frandom(-jerkamt,jerkamt);
			A_MuzzleClimb(
				(0,0),
				(frandom(0,jerkleft),frandom(0,jerkdown)),
				(frandom(0,jerkleft),frandom(0,jerkdown)),
				(0,0)
			);
			AddBlackout(128,damage+(bash?32:16),16);
		}


		//brute force a reset in nobleed mode
		//there are multiple sources of bloodloss
		if(hd_nobleed)bloodloss=0;


		//disintegrator mode keeps things simple
		if(
			hd_disintegrator
			||hd_nobleed
		)return super.DamageMobj(
			inflictor,
			source,
			damage,
			mod,
			flags|DMG_NO_ARMOR,
			angle
		);


		//player survives at cost
		if(
			damage>=health
		){
			if(
				mod!="internal"
				&&mod!="bleedout"
				&&damage<random(10,100)
				&&random(0,5)
			){
				int wnddmg=random(0,max(0,damage>>2));
				if(mod=="bashing")wnddmg>>=1;
				damage=health-random(1,3);
				if(
					mod=="hot"
					||mod=="cold"
				){
					burncount+=wnddmg;
				}else if(
					mod=="slime"
					||mod=="balefire"
				){
					aggravateddamage+=wnddmg;
				}else{
					oldwoundcount+=wnddmg;
				}
			}
		}


		//finally call the real one but ignore all armour
		int finaldmg=super.DamageMobj(
			inflictor,
			source,
			damage,
			mod,
			flags|DMG_NO_ARMOR,
			angle
		);

		//transfer pointers to corpse
		if(deathcounter&&inflictor&&!inflictor.bismonster&&playercorpse){
			if(inflictor.tracer==self)inflictor.tracer=playercorpse;
			if(inflictor.target==self)inflictor.target=playercorpse;
			if(inflictor.master==self)inflictor.master=playercorpse;
		}

		//go into dying/collapsed mode
		if(
			health>0
			&&player
			&&incapacitated<1
			&&(
				health<random(-1,max((originaldamage>>3),3))
				||tostun>(health<<2)
			)&&(
				mod!="bleedout"
				||bloodloss>random(2048,3072)
			)
		)A_Incapacitated((originaldamage>10)?HDINCAP_SCREAM:0,min(finaldmg<<5,originaldamage<<3));


		return finaldmg;
	}
	//disarm
	static void Disarm(actor victim){
		if(!victim.player)return;
		let pwep=hdweapon(victim.player.readyweapon);
		if(!pwep)return;
		pwep.OnPlayerDeathOrIncap();
		if(
			pwep
			&&pwep.owner==victim //onplayerdrop might change this
			&&!pwep.bdontdisarm
		){
			victim.DropInventory(pwep);
		}
	}
	states{
	pain:
	pain.drowning:
	pain.falling:
	painend:
		#### G 3{
			if(!inpain){
				inpain=3;
				if(bloodpressure<100)bloodpressure+=20;
				if(beatmax>12)beatmax=max(beatmax-randompick(10,20),8);
			}
			if(incapacitated)frame=clamp(6+abs(incapacitated>>2),6,11);
		}
		---- A 3{
			if(
				!incapacitated
				||!random(0,3)
			)A_StartSound(painsound,CHAN_VOICE);
		}
		---- A 0 setstatelabel("spawn");
	pain.slime:
		#### G 3{
			if(bloodpressure<40)bloodpressure+=2;
			if(beatmax>20)beatmax=max(beatmax-2,18);
			A_SetBlend("00 00 00",0.8,40,"00 00 00");
		}
		#### G 3 A_StartSound(painsound,CHAN_VOICE);
		---- A 0 setstatelabel("spawn");
	}
}


//for future reference
class DamageFloorChecker:Actor{
	override void postbeginplay(){
		super.postbeginplay();
		sector sss=floorsector;
		A_Log(string.format(
			"%i %s damage every %i tics with %i leak chance.",
			sss.damageamount,
			sss.damagetype,
			sss.damageinterval,
			sss.leakydamage
		));
		destroy();
	}
}
