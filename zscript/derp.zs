// ------------------------------------------------------------
// D.E.R.P. Robot
// ------------------------------------------------------------

/*
	NOTE FOR MAPPERS
	You can set mode using user_cmd.
	0=random (default), see DerpConst below for the others
*/

const DERP_CONTROLRANGE=HDCONST_ONEMETRE*200.;
enum DerpConst{
	DERP_IDLE=1,
	DERP_WATCH=2,
	DERP_TURRET=3,
	DERP_PATROL=4,

	DERP_HEEL=DERP_PATROL+1,
	DERP_GO=DERP_HEEL+1,

	DERP_RANGE=320,
	DERP_MAXTICTURN=15,
	DERPS_MODE=1,
	DERPS_USEOFFS=2,
	DERPS_AMMO=3,
	DERPS_BOTID=4,
	DERPS_CMD=5,
	DERPF_BROKEN=1,
}
enum DERPControllerNums{
	DRPCS_INDEX=1,
	DRPCS_TIMER=3,
}
class DERPBot:HDUPK{
	int user_cmd;
	int cmd;
	int oldcmd;
	int ammo;
	int botid;
	default{
		//$Category "Monsters/Hideous Destructor"
		//$Title "D.E.R.P. Robot"
		//$Sprite "DERPA1"
		+ismonster +noblockmonst +shootable
		+friendly +nofear +dontgib +noblood +ghost
		+nobouncesound
		painchance 240;painthreshold 12;
		speed 3;
		damagefactor "hot",0.7;
		damagefactor "cold",0.7;
		damagefactor "Normal",0.8;
		radius 4;height 8;deathheight 8;maxdropoffheight 4;maxstepheight 4;
		bloodcolor "22 22 22";scale 0.6;
		health 100;mass 20;
		maxtargetrange DERP_RANGE;
		hdupk.pickupsound "derp/crawl";
		hdupk.pickupmessage ""; //let the pickup do this
		obituary "$OB_DERP";
		tag "$TAG_DERP";
	}
	override bool cancollidewith(actor other,bool passive){return other.bmissile||HDPickerUpper(other)||DERPBot(other);}
	bool DerpTargetCheck(bool face=false){
		if(!target)return false;
		//mitigate hot starts
		//8s *should* be enough to handle most wandering???
		if(
			target.player
			&&level.time<(TICRATE<<3)
		){
			cmd=DERP_IDLE;
			setstatelabel("spawn");
			return false;
		}

		//don't target friendlies
		if(
			target==master
			||(master&&target.isteammate(master))
		){
			A_ClearTarget();
			A_SetFriendly(true);
			setstatelabel("spawn");
			return false;
		}
		if(face){
			A_StartSound("derp/crawl");
			A_FaceTarget(2,2,FAF_TOP);
		}
		flinetracedata dlt;
		linetrace(
			angle,DERP_RANGE,pitch,
			offsetz:2,
			data:dlt
		);
		return(dlt.hitactor==target);
	}
	void DerpAlert(string msg="Derpy derp!"){
		if(master)master.A_Log(Stringtable.Localize("$DERP_ALERT2")..(botid?Stringtable.Localize("$DERP_ALERT3")..botid..Stringtable.Localize("$DERP_ALERT4"):"")..Stringtable.Localize("$DERP_ALERT5")..msg,true);
	}
	void DerpShot(){
		A_StartSound("weapons/pistol",CHAN_WEAPON);
		if(!random(0,11)){
			if(bfriendly)A_AlertMonsters(0,AMF_TARGETEMITTER);
			else A_AlertMonsters();
		}
		HDBulletActor.FireBullet(self,"HDB_9",zofs:2,spread:2.,speedfactor:frandom(0.97,1.03));
		pitch+=frandom(-1.,1.);angle+=frandom(-1.,1.);
	}
	void A_DerpAttack(){
		if(DerpTargetCheck(false))DerpShot();
	}
	void A_DerpLook(int flags=0,statelabel seestate="see"){
		A_ClearTarget();
		if(cmd==DERP_IDLE)return;
		A_LookEx(flags|LOF_NOSOUNDCHECK,label:seestate);
		if(
			deathmatch
			&&bfriendly
			&&master
			&&master.player
		){
			for(int i=0;i<MAXPLAYERS;i++){
				if(
					playeringame[i]
					&&players[i].mo
					&&players[i].mo!=master
					&&(!teamplay||players[i].getteam()!=master.player.getteam())
					&&distance3dsquared(players[i].mo)<(DERP_RANGE*DERP_RANGE)
				){
					A_SetFriendly(false);
					target=players[i].mo;
					if(!(flags&LOF_NOJUMP))setstatelabel(seestate);
					break;
				}
			}
		}
		if(
				flags&LOF_NOJUMP
				&&target
				&&target.health>0
				&&checksight(target)
			)setstatelabel("missile");
	}
	int movestamina;
	double goalangle;
	vector2 goalpoint;
	vector2 originalgoalpoint;
	double angletogoal(){
		vector2 vecdiff=level.vec2diff(pos.xy,goalpoint);
		return atan2(vecdiff.y,vecdiff.x);
	}
	void A_DerpCrawlSound(int chance=50){
		A_StartSound("derp/crawl",CHAN_BODY);
		if(bfriendly&&!random(0,50))A_AlertMonsters(0,AMF_TARGETEMITTER);
	}
	void A_DerpCrawl(bool attack=true){
		bool moved=true;
		//wait(1) does nothing, not even make noise
		if(attack&&cmd!=DERP_IDLE){
			if(target&&target.health>0)A_Chase(
				"missile","missile",CHF_DONTMOVE|CHF_DONTTURN|CHF_NODIRECTIONTURN
			);
		}
		if(
			cmd==DERP_PATROL
			||movestamina<20
		){
			A_DerpCrawlSound();
			moved=TryMove(pos.xy+(cos(angle),sin(angle))*speed,false);
			movestamina++;
		}else if(
			cmd==DERP_TURRET
		){
			A_DerpCrawlSound();
			A_SetAngle(angle+36,SPF_INTERPOLATE);
		}
		if(!moved){
			goalangle=angle+frandom(30,120)*randompick(-1,1);
		}else if(
			movestamina>20
			&&movestamina<1000
			&&!random(0,23)
		){
			goalangle=angletogoal();
			if(cmd==DERP_PATROL){
				goalangle+=frandom(-110,110);
				movestamina=0;
			}
		}else goalangle=999;
		if(moved&&stuckline){
			setstatelabel("unstucknow");
			return;
		}
		if(goalangle!=999)setstatelabel("Turn");
	}
	void A_DerpTurn(){
		if(goalangle==999){
			setstatelabel("see");
			return;
		}
		A_DerpCrawlSound();
		double norm=deltaangle(goalangle,angle);
		if(abs(norm)<DERP_MAXTICTURN){
			angle=goalangle;
			goalangle=999;
			return;
		}
		if(norm<0){
			A_SetAngle(angle+DERP_MAXTICTURN,SPF_INTERPOLATE);
		}else{
			A_SetAngle(angle-DERP_MAXTICTURN,SPF_INTERPOLATE);
		}
	}
	line stuckline;
	sector stuckbacksector;
	double stuckheight;
	int stucktier;
	vector2 stuckpoint;
	void A_DerpStuck(){
		setz(
			stucktier==1?stuckbacksector.ceilingplane.zatpoint(stuckpoint)+stuckheight:
			stucktier==-1?stuckbacksector.floorplane.zatpoint(stuckpoint)+stuckheight:
			stuckheight
		);
		if(
			!stuckline
			||doordestroyer.IsBrokenWindow(stuckline,stucktier)
			||ceilingz<pos.z
			||floorz>pos.z
		){
			stuckline=null;
			setstatelabel("unstucknow");
			return;
		}
	}

	override int damagemobj(
		actor inflictor,actor source,int damage,
		name mod,int flags,double angle
	){
		if(
			!!source
			&&(
				!inflictor
				||source==inflictor
			)
			&&source.health>0
			&&source.bismonster
			&&source.bcanusewalls
			&&(
				source.instatesequence(source.curstate,source.resolvestate("melee"))
				||source.instatesequence(source.curstate,source.resolvestate("meleekick"))
			)
		){
			target=source;
			setz(target.pos.z+target.height*0.7);
			if(!instatesequence(curstate,resolvestate("give")))setstatelabel("give");
			return -1;
		}
		return super.damagemobj(inflictor,source,damage,mod,flags,angle);
	}

	override void postbeginplay(){
		super.postbeginplay();
		originalgoalpoint=pos.xy;
		goalpoint=originalgoalpoint;
		goalangle=999;
		if(!master||!master.player){
			ammo=15;
			if(user_cmd)cmd=user_cmd;
			else cmd=random(1,4);
		}
		if(
			cmd<DERP_PATROL
		)movestamina=1001;
		oldcmd=cmd;
	}
	states{
	stuck:
		DERP A 1 A_DerpStuck();
		wait;
	unstuck:
		DERP A 2 A_JumpIf(!stuckline,"unstucknow");
		DERP A 4 A_StartSound("derp/crawl",16);
	unstucknow:
		DERP A 2 A_StartSound("misc/fragknock",15);
		DERP A 10{
			if(stuckline){
				bool exiting=
					stuckline.special==Exit_Normal
					||stuckline.special==Exit_Secret;
				if(
					!exiting||!master||(
						checksight(master)
						&&distance3d(master)<128
					)
				){
					stuckline.activate(master,0,SPAC_Use);
					if(exiting&&master)master.A_GiveInventory("DERPUsable",1);
				}
			}
			stuckline=null;
			spawn("FragPuff",pos,ALLOW_REPLACE);
			bnogravity=false;
			A_ChangeVelocity(3,0,2,CVF_RELATIVE);
			A_StartSound("weapons/bigcrack",14);
		}goto spawn2;
	give:
		DERP A 0{
			stuckline=null;bnogravity=false;
			oldcmd=cmd;
			if(cmd!=DERP_IDLE){
				A_StartSound("weapons/rifleclick2",CHAN_AUTO);
				cmd=DERP_IDLE;
			}
			let ddd=DERPUsable(spawn("DERPUsable",pos));
			if(ddd){
				ddd.weaponstatus[DERPS_AMMO]=ammo;
				ddd.weaponstatus[DERPS_BOTID]=botid;
				ddd.weaponstatus[DERPS_MODE]=oldcmd;
				if(health<1)ddd.weaponstatus[0]|=DERPF_BROKEN;
				ddd.translation=self.translation;
				grabthinker.grab(target,ddd);
			}
			destroy();
			DERPController.GiveController(target);
			return;
		}goto spawn;
	spawn:
		DERP A 0 nodelay A_JumpIf(!!stuckline,"stuck");
	spawn2:
		DERP A 0 A_ClearTarget();
		DERP A 0 A_DerpLook();
		DERP A 3 A_DerpCrawl();
		loop;
	see:
		DERP A 0 A_ClearTarget();
		DERP A 0 A_JumpIf(ammo<1&&movestamina<1&&goalangle==-999,"noammo");
	see2:
		DERP A 2 A_DerpCrawl();
		DERP A 0 A_DerpLook(LOF_NOJUMP);
		DERP A 2 A_DerpCrawl();
		DERP A 0 A_DerpLook(LOF_NOJUMP);
		DERP A 2 A_DerpCrawl();
		DERP A 0 A_DerpLook(LOF_NOJUMP);
		DERP A 2 A_DerpCrawl();
		DERP A 0 A_DerpLook(LOF_NOJUMP);
		---- A 0 setstatelabel("see");
	turn:
		DERP A 1 A_DerpTurn();
		wait;
	noshot:
		DERP AAAAAAAA 2 A_DerpCrawl();
		---- A 0 setstatelabel("see2");
	pain:
		DERP A 20{
			A_StartSound("derp/crawl",CHAN_BODY);
			angle+=randompick(1,-1)*random(2,8)*10;
			pitch-=random(10,20);
		}
	missile:
	ready:
		DERP A 0 A_StartSound("derp/crawl",CHAN_BODY,volume:0.6);
		DERP AAA 1 A_FaceTarget(20,20,0,0,FAF_TOP,-4);
		DERP A 0 A_JumpIf(cmd==DERP_IDLE,"spawn");
		DERP A 0 A_JumpIfTargetInLOS(1,1);
		loop;
	aim:
		DERP A 2 A_JumpIf(!DerpTargetCheck(),"noshot");
		DERP A 0 DerpAlert(Stringtable.Localize("$DERP_AIM"));
	fire:
		DERP A 0 A_JumpIfHealthLower(1,"dead");
		DERP A 0 A_JumpIf(ammo>0,"noreallyfire");
		goto noammo;
	noreallyfire:
		DERP C 1 bright light("SHOT") DerpShot();
		DERP D 1 A_SpawnItemEx("HDSpent9mm", -3,1,-1, random(-1,-3),random(-1,1),random(-3,-4), 0,SXF_NOCHECKPOSITION|SXF_SETTARGET);
		DERP A 4{
			if(getzat(0)<pos.z) A_ChangeVelocity(cos(pitch)*-2,0,sin(pitch)*2,CVF_RELATIVE);
			else A_ChangeVelocity(cos(pitch)*-0.4,0,sin(pitch)*0.4,CVF_RELATIVE);
			ammo--;
		}
		DERP A 1{
			A_FaceTarget(10,10,0,0,FAF_TOP,-4);
			if(target&&target.health<1){
				DerpAlert(Stringtable.Localize("$DERP_KILL"));
			}
		}
	yourefired:
		DERP A 0 A_JumpIf(
			!target
			||target.health<1
			||cmd==DERP_IDLE
		,"see");
		DERP A 0 A_JumpIfTargetInLOS("fire",2,JLOSF_DEADNOJUMP,DERP_RANGE,0);
		DERP A 0 A_JumpIfTargetInLOS("aim",360,JLOSF_DEADNOJUMP,DERP_RANGE,0);
		goto noshot;
	death:
		DERP A 0{
			DerpAlert(Stringtable.Localize("$DERP_STANDBY"));
			A_StartSound("weapons/bigcrack",CHAN_VOICE);
			A_SpawnItemEx("HDSmoke",0,0,1, vel.x,vel.y,vel.z+1, 0,SXF_NOCHECKPOSITION|SXF_ABSOLUTEMOMENTUM);
			A_SpawnChunks("BigWallChunk",12);
		}
	dead:
		DERP A -1;
	noammo:
		DERP A 10{
			A_ClearTarget();
			DerpAlert(Stringtable.Localize("$DERP_NOAMMO"));
		}goto spawn;
	}
}
//usable has separate actors to preserve my own sanity
class DERPUsable:HDWeapon{
	default{
		//$Category "Items/Hideous Destructor"
		//$Title "D.E.R.P. Robot (Pickup)"
		//$Sprite "DERPA1"
		+weapon.wimpy_weapon
		+weapon.no_auto_switch
		+inventory.invbar
		+hdweapon.droptranslation
		+hdweapon.fitsinbackpack
		hdweapon.barrelsize 0,0,0;
		weapon.selectionorder 1014;
		scale 0.6;
		inventory.icon "DERPEX";
		inventory.pickupmessage "$PICKUP_DERP";
		inventory.pickupsound "derp/crawl";
		translation 0;
		tag "$TAG_DERP";
		hdweapon.refid "drp";
		hdweapon.ammo1 "HD9mMag15",1;
		hdweapon.incapweapon "IncapDERP";
	}
	override bool AddSpareWeapon(actor newowner){return AddSpareWeaponRegular(newowner);}
	override hdweapon GetSpareWeapon(actor newowner,bool reverse,bool doselect){return GetSpareWeaponRegular(newowner,reverse,doselect);}
	override int getsbarnum(int flags){
		let ssbb=HDStatusBar(statusbar);
		if(ssbb&&weaponstatus[0]&DERPF_BROKEN)ssbb.savedcolour=Font.CR_DARKGRAY;
		return weaponstatus[DERPS_BOTID];
	}
	override void InitializeWepStats(bool idfa){
		weaponstatus[DERPS_BOTID]=1;
		weaponstatus[DERPS_AMMO]=15;
		weaponstatus[DERPS_MODE]=DERP_TURRET;
		if(idfa)weaponstatus[0]&=~DERPF_BROKEN;
	}
	override void loadoutconfigure(string input){
		int mode=getloadoutvar(input,"mode",1);
		if(mode>0)weaponstatus[DERPS_MODE]=clamp(mode,1,3);
		mode=getloadoutvar(input,"unloaded",1);
		if(mode>0)weaponstatus[DERPS_AMMO]=-1;
	}
	override double weaponbulk(){
		int mgg=weaponstatus[DERPS_AMMO];
		return ENC_DERP+(mgg<0?0:(ENC_9MAG_LOADED+mgg*ENC_9_LOADED));
	}
	override string pickupmessage(){
		string msg=super.pickupmessage();
		if(weaponstatus[0]&DERPF_BROKEN)return msg..Stringtable.Localize("$PICKUP_DERP_BROKEN");
		return msg;
	}
	override void detachfromowner(){
		translation=owner.translation;
		super.detachfromowner();
	}
	override void DrawHUDStuff(HDStatusBar sb,HDWeapon hdw,HDPlayerPawn hpl){
		int ofs=weaponstatus[DERPS_USEOFFS];
		if(ofs>90)return;
		let ddd=DERPUsable(owner.findinventory("DERPUsable"));
		if(!ddd||ddd.amount<1)return;
		let pmags=HD9mMag15(owner.findinventory("HD9mMag15"));
		vector2 bob=hpl.wepbob*0.2;
		bob.y+=ofs;
		sb.drawimage("DERPA8A2",(0,22)+bob,
			sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER|sb.DI_TRANSLATABLE,
			alpha:!!pmags?1.:0.6,scale:(2,2)
		);
		if(ofs>30)return;
		int mno=hdw.weaponstatus[DERPS_MODE];
		string mode;
		if(hdw.weaponstatus[0]&DERPF_BROKEN)mode=Stringtable.Localize("$DERP_BROKEN");
		else if(mno==DERP_IDLE)mode=Stringtable.Localize("$DERP_WAIT");
		else if(mno==DERP_WATCH)mode=Stringtable.Localize("$DERP_LINE");
		else if(mno==DERP_TURRET)mode=Stringtable.Localize("$DERP_TURRET");
		else if(mno==DERP_PATROL)mode=Stringtable.Localize("$DERP_PATROL");
		sb.drawstring(
			sb.psmallfont,mode,(0,34)+bob,
			sb.DI_TEXT_ALIGN_CENTER|sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER
		);
		sb.drawstring(
			sb.psmallfont,Stringtable.Localize("$DERP_BOTID")..ddd.weaponstatus[DERPS_BOTID],(0,44)+bob,
			sb.DI_TEXT_ALIGN_CENTER|sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER
		);
		if(weaponstatus[DERPS_AMMO]<0)mode=Stringtable.Localize("$DERP_NOMAG");
		else mode=Stringtable.Localize("$DERP_MAG")..weaponstatus[DERPS_AMMO];
		sb.drawstring(
			sb.psmallfont,mode,(0,54)+bob,
			sb.DI_TEXT_ALIGN_CENTER|sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER
		);
		if(sb.hudlevel==1){
			int nextmagloaded=sb.GetNextLoadMag(hdmagammo(hpl.findinventory("HD9mMag15")));
			if(nextmagloaded>=15){
				sb.drawimage("CLP2NORM",(-46,-3),sb.DI_SCREEN_CENTER_BOTTOM,scale:(1,1));
			}else if(nextmagloaded<1){
				sb.drawimage("CLP2EMPTY",(-46,-3),sb.DI_SCREEN_CENTER_BOTTOM,alpha:nextmagloaded?0.6:1.,scale:(1,1));
			}else sb.drawbar(
				"CLP2NORM","CLP2GREY",
				nextmagloaded,15,
				(-46,-3),-1,
				sb.SHADER_VERT,sb.DI_SCREEN_CENTER_BOTTOM
			);
			sb.drawnum(hpl.countinv("HD9mMag15"),-43,-8,sb.DI_SCREEN_CENTER_BOTTOM,font.CR_BLACK);
		}
		sb.drawwepnum(hdw.weaponstatus[DERPS_AMMO],15);
	}
	override string gethelptext(){
		LocalizeHelp();
		return
		((weaponstatus[0]&DERPF_BROKEN)?
		(LWPHELP_FIRE.."+"..LWPHELP_RELOAD..StringTable.Localize("$DERPWH_REPAIR")):(LWPHELP_FIRE..StringTable.Localize("$DERPWH_FIRE")))
		..LWPHELP_ALTFIRE..StringTable.Localize("$DERPWH_ALTFIRE")
		..LWPHELP_FIREMODE.."+"..LWPHELP_UPDOWN..StringTable.Localize("$DERPWH_FMODPUD")
		..LWPHELP_RELOADRELOAD
		..LWPHELP_UNLOADUNLOAD
		;
	}
	action void A_AddOffset(int ofs){
		invoker.weaponstatus[DERPS_USEOFFS]+=ofs;
	}
	override void consolidate(){
		if(!owner)return;
		let spw=spareweapons(owner.findinventory("spareweapons"));
		if(spw){
			for(int i=0;i<spw.weapontype.size();i++){
				if(spw.weapontype[i]!=getclassname())continue;
				array<string>wpst;wpst.clear();
				spw.weaponstatus[i].split(wpst,",");
				int wpstint=wpst[0].toint();
				if(
					wpstint&DERPF_BROKEN
				){
					if(!random(0,7)){
						wpstint&=~DERPF_BROKEN;
						owner.A_Log(Stringtable.Localize("$DERP_REPAIR"),true);
						string newwepstat=spw.weaponstatus[i];
						newwepstat=wpstint..newwepstat.mid(newwepstat.indexof(","));
						spw.weaponstatus[i]=newwepstat;
					}
				}
			}
		}
		if(
			(weaponstatus[0]&DERPF_BROKEN)
			&&!random(0,7)
		){
			weaponstatus[0]&=~DERPF_BROKEN;
			owner.A_Log(Stringtable.Localize("$DERP_FIELDREPAIR"),true);
		}
	}
	override void DropOneAmmo(int amt){
		if(owner){
			amt=clamp(amt,1,10);
			if(owner.countinv("HDPistolAmmo"))owner.A_DropInventory("HDPistolAmmo",amt*15);
			else owner.A_DropInventory("HD9mMag15",amt);
		}
	}
	override void ForceBasicAmmo(){
		owner.A_TakeInventory("HDPistolAmmo");
		owner.A_TakeInventory("HD9mMag15");
		owner.A_GiveInventory("HD9mMag15",1);
	}
	override void postbeginplay(){
		super.postbeginplay();
		if(
			owner
			&&owner.player
			&&owner.getage()<5
		)weaponstatus[DERPS_MODE]=cvar.getcvar("hd_derpmode",owner.player).getint();
	}
	states{
	spawn:
		DERP A -1;
		stop;
	select:
		TNT1 A 0 A_AddOffset(100);
		goto super::select;
	ready:
		TNT1 A 1{
			if(pressinguser3()){
				A_MagManager("HD9mMag15");
				return;
			}
			int iofs=invoker.weaponstatus[DERPS_USEOFFS];
			if(iofs>0)invoker.weaponstatus[DERPS_USEOFFS]=iofs*2/3;
			if(pressingfiremode()){
				int ptch=
					(GetMouseY(true)>>4)
					+(justpressed(BT_ATTACK)?1:justpressed(BT_ALTATTACK)?-1:0)
				;
				if(ptch){
					invoker.weaponstatus[DERPS_BOTID]=clamp(
						ptch+invoker.weaponstatus[DERPS_BOTID],0,63
					);
				}
			}
			else if(justpressed(BT_ALTATTACK)){
				int mode=invoker.weaponstatus[DERPS_MODE];
				if(pressinguse())mode--;else mode++;
				if(mode<1)mode=DERP_PATROL;
				else if(mode>DERP_PATROL)mode=1;
				invoker.weaponstatus[DERPS_MODE]=mode;
				return;
			}
			else if(pressingfire()){
				setweaponstate("deploy");
				return;
			}
			A_WeaponReady(WRF_NOFIRE|WRF_ALLOWRELOAD|WRF_ALLOWUSER4);
		}goto readyend;
	deploy:
		TNT1 AA 1 A_AddOffset(4);
		TNT1 AAAA 1 A_AddOffset(9);
		TNT1 AAAA 1 A_AddOffset(20);
		TNT1 A 0 A_JumpIf(!pressingfire(),"ready");
		TNT1 A 4 A_StartSound("weapons/pismagclick",CHAN_WEAPON);
		TNT1 A 2 A_StartSound("derp/crawl",CHAN_WEAPON,CHANF_OVERLAP);
		TNT1 A 1{
			if(invoker.weaponstatus[0]&DERPF_BROKEN){
				setweaponstate("readytorepair");
				return;
			}
			//stick it to a door
			if(pressingzoom()){
				int cid=countinv("DERPUsable");
				let hhh=hdhandlers(eventhandler.find("hdhandlers"));
				hhh.SetDERP(hdplayerpawn(self),555,invoker.weaponstatus[DERPS_BOTID],0);
				return;
			}
			actor a;int b;
			[b,a]=A_SpawnItemEx("DERPBot",12,0,gunheight()-4,
				cos(pitch)*6,0,-sin(pitch)*6,0,
				SXF_NOCHECKPOSITION|SXF_TRANSFERPOINTERS|
				SXF_SETMASTER|SXF_TRANSFERTRANSLATION|SXF_SETTARGET
			);
			let derp=derpbot(a);
			derp.vel+=vel;
			derp.cmd=invoker.weaponstatus[DERPS_MODE];
			derp.botid=invoker.weaponstatus[DERPS_BOTID];
			derp.ammo=invoker.weaponstatus[DERPS_AMMO];
			DERPController.GiveController(self);
			dropinventory(invoker);
			invoker.goawayanddie();
		}
		goto nope;
	unload:
		TNT1 A 6 A_JumpIf(invoker.weaponstatus[DERPS_AMMO]<0,"nope");
		TNT1 A 3 A_StartSound("pistol/pismagclick",CHAN_WEAPONBODY);
		TNT1 A 0{
			int ammount=invoker.weaponstatus[DERPS_AMMO];
			if(pressingunload())HDMagAmmo.GiveMag(self,"HD9mMag15",ammount);
			else{
				HDMagAmmo.SpawnMag(self,"HD9mMag15",ammount);
				setweaponstate("nope");
			}
			invoker.weaponstatus[DERPS_AMMO]=-1;
		}
		TNT1 A 20 A_StartSound("weapons/pocket",CHAN_POCKETS);
		goto nope;
	reload:
		TNT1 A 0 A_JumpIf(invoker.weaponstatus[DERPS_AMMO]>=0,"nope");
		TNT1 A 20 A_StartSound("weapons/pocket",CHAN_POCKETS);
		TNT1 A 10 A_JumpIf(HDMagAmmo.NothingLoaded(self,"HD9mMag15"),"nope");
		TNT1 A 6{
			A_StartSound("pistol/pismagclick",CHAN_WEAPONBODY);
			invoker.weaponstatus[DERPS_AMMO]=HDMagAmmo(findinventory("HD9mMag15")).TakeMag(true);
		}
		goto nope;
	readytorepair:
		TNT1 A 1{
			if(!pressingfire())setweaponstate("nope");
			else if(PressingReload()){
				if(invoker.weaponstatus[DERPS_AMMO]>=0){
					A_Log(Stringtable.Localize("$DERP_REMOVEMAG"),true);
				}else setweaponstate("repairbash");
			}
		}
		wait;
	repairbash:
		TNT1 A 10{
			int failchance=40;
			int spareindex=-1;
			//find spares, whether to cannibalize or copy
			let spw=spareweapons(findinventory("spareweapons"));
			if(spw){
				for(int i=0;i<spw.weapontype.size();i++){
					if(
						spw.weapontype[i]==getclassname()
						&&spw.GetWeaponValue(i,0)&DERPF_BROKEN
					){
						if(spareindex==-1)spareindex=i;
						failchance=min(10,failchance-7);
						break;
					}
				}
			}
			if(!random(0,failchance)){
				invoker.weaponstatus[0]&=~DERPF_BROKEN;
				A_SetHelpText();
				A_StartSound("derp/repair",CHAN_WEAPON);
				A_Log(Stringtable.Localize("$DERP_REPAIRED"),true);
				//destroy one spare
				if(
					spareindex>=0
					&&!random(0,2)
				){
					spw.weaponbulk.delete(spareindex);
					spw.weapontype.delete(spareindex);
					spw.weaponstatus.delete(spareindex);
					A_Log(Stringtable.Localize("$DERP_CANNIBALIZED"),true);
				}
			}else A_StartSound("derp/repairtry",CHAN_WEAPONBODY,CHANF_OVERLAP,
				volume:frandom(0.6,1.),pitch:frandom(1.2,1.4)
			);
			A_MuzzleClimb(
				frandom(-1.,1.),frandom(-1.,1.),
				frandom(-1.,1.),frandom(-1.,1.),
				frandom(-1.,1.),frandom(-1.,1.),
				frandom(-1.,1.),frandom(0.,1.),
				wepdot:false
			);
		}
		TNT1 A 0 A_JumpIf(!(invoker.weaponstatus[0]&DERPF_BROKEN),"nope");
		goto readytorepair;
	}
}
//evil roguebot
class EnemyDERP:DERPBot{
	default{
		//$Category "Monsters/Hideous Destructor"
		//$Title "D.E.R.P. Robot (Hostile)"
		//$Sprite "DERPA1"
		-friendly
		translation 1;
	}
}
//damaged robot to place on maps
class DERPDead:EnemyDERP{
	default{
		//$Category "Monsters/Hideous Destructor"
		//$Title "D.E.R.P. Robot (Dead)"
		//$Sprite "DERPA1"
	}
	override void postbeginplay(){
		super.postbeginplay();
		A_Die();
	}
	states{
	death:
		DERP A -1;
		stop;
	}
}
extend class HDHandlers{
	void HackDERP(hdplayerpawn ppp,int cmd,int tag,int cmd2){
		let dpu=DERPController(ppp.findinventory("DERPController"));
		if(
			dpu
			&&ppp.player
			&&ppp.player.readyweapon==dpu
		)dpu.setownerweaponstate("hack");
		else ppp.A_Log(Stringtable.Localize("$DERP_NOINTERFACE"),true);
	}
	void SetDERP(hdplayerpawn ppp,int cmd,int tag,int cmd2){
		if(cmd<0){
			let dpu=DERPUsable(ppp.findinventory("DERPUsable"));
			if(dpu){
				dpu.weaponstatus[DERPS_BOTID]=-cmd;
				ppp.A_Log(string.format(Stringtable.Localize("$DERP_TAGSET"),-cmd),true);
			}
			return;
		}
		else if(cmd==1024){
			ppp.A_SetInventory("DERPController",1);
			ppp.UseInventory(ppp.findinventory("DERPController"));
			return;
		}
		else if(cmd==555){
			let dpu=DERPUsable(ppp.findinventory("DERPUsable"));
			if(!dpu)return;
			if(dpu.weaponstatus[0]&DERPF_BROKEN){
				ppp.A_Log(string.format(Stringtable.Localize("$DERP_ITSBROKEN")),true);
				return;
			}
			flinetracedata dlt;
			ppp.linetrace(
				ppp.angle,48,ppp.pitch,flags:TRF_THRUACTORS,
				offsetz:ppp.height*0.8,
				data:dlt
			);
			if(
				!dlt.hitline
				||HDF.linetracehitsky(dlt)
			){
				ppp.A_Log(string.format(Stringtable.Localize("$DERP_555HELP")),true);
				return;
			}
			let ddd=DERPBot(ppp.spawn("DERPBot",dlt.hitlocation-dlt.hitdir*4,ALLOW_REPLACE));
			if(!ddd){
				ppp.A_Log(string.format(Stringtable.Localize("$DERP_CANTDEPLOY")),true);
				return;
			}
			ddd.botid=tag?abs(tag):dpu.weaponstatus[DERPS_BOTID];
			ddd.A_StartSound("misc/bulletflesh",CHAN_BODY,CHANF_OVERLAP);
			ddd.stuckline=dlt.hitline;
			ddd.bnogravity=true;
			ddd.translation=ppp.translation;
			ddd.master=ppp;
			ddd.ammo=dpu.weaponstatus[DERPS_AMMO];
			let delta=-dlt.hitline.delta;
			if(dlt.lineside==line.back)delta=-delta;
			ddd.angle=VectorAngle(-delta.y,delta.x);
			if(!dlt.hitline.backsector){
				ddd.stuckheight=ddd.pos.z;
				ddd.stucktier=0;
			}else{
				sector othersector=hdmath.oppositesector(dlt.hitline,dlt.hitsector);
				ddd.stuckpoint=dlt.hitlocation.xy+dlt.hitdir.xy*4;
				double stuckceilingz=othersector.ceilingplane.zatpoint(ddd.stuckpoint);
				double stuckfloorz=othersector.floorplane.zatpoint(ddd.stuckpoint);
				ddd.stuckbacksector=othersector;
				double dpz=ddd.pos.z;
				if(dpz-ddd.height>stuckceilingz){
					ddd.stuckheight=dpz-ddd.height-stuckceilingz;
					ddd.stucktier=1;
				}else if(dpz<stuckfloorz){
					ddd.stuckheight=dpz-stuckfloorz;
					ddd.stucktier=-1;
				}else{
					ddd.stuckheight=ddd.pos.z;
					ddd.stucktier=0;
				}
			}
			DERPController.GiveController(ppp);
			ppp.dropinventory(dpu);
			dpu.destroy();
			return;
		}
		ThinkerIterator it=ThinkerIterator.Create("DERPBot");
		actor bot=null;
		int derps=0;
		bool badcommand=true;
		while(bot=DERPBot(it.Next())){
			let derp=DERPBot(bot);
			if(
				!!derp
				&&derp.master==ppp
				&&derp.health>0
				&&(!tag||tag==derp.botid)
			){
				bool goalset=false;
				if(cmd&&cmd<=DERP_PATROL){
					badcommand=false;
					derp.cmd=cmd;
					derp.oldcmd=cmd;
					string mode;
					if(cmd==DERP_IDLE){
						mode=Stringtable.Localize("$DERP_MODEWAIT");
						derp.movestamina=1001;
					}
					else if(cmd==DERP_WATCH){
						mode=Stringtable.Localize("$DERP_MODELINE");
						derp.movestamina=1001;
					}
					else if(cmd==DERP_TURRET){
						mode=Stringtable.Localize("$DERP_MODETURRET");
						derp.movestamina=1001;
					}
					else if(cmd==DERP_PATROL){
						mode=Stringtable.Localize("$DERP_MODEPATROL");
						derp.movestamina=0;
					}
					ppp.A_Log(string.format(Stringtable.Localize("$DERP_MODE"),mode),true);
				}else if(cmd==DERP_HEEL){
					badcommand=false;
					goalset=true;
					derp.goalpoint=ppp.pos.xy;
					ppp.A_Log(Stringtable.Localize("$DERP_GOALSETPLAYER"),true);
				}else if(cmd==DERP_GO){
					badcommand=false;
					flinetracedata derpgoal;
					ppp.linetrace(
						ppp.angle,2048,ppp.pitch,
						TRF_NOSKY,
						offsetz:ppp.height*0.8,
						data:derpgoal
					);
					if(derpgoal.hittype!=Trace_HitNone){
						goalset=true;
						derp.goalpoint=derpgoal.hitlocation.xy;
						ppp.A_Log(string.format(Stringtable.Localize("$DERP_GOALSETTO"),derpgoal.hitlocation.x,derpgoal.hitlocation.y),true);
					}
				}else if(cmd>800&&cmd<810){
					badcommand=false;
					vector2 which;
					switch(cmd-800){
						case 1:which=(-1,-1);break;
						case 2:which=(0,-1);break;
						case 3:which=(1,-1);break;
						case 4:which=(-1,0);break;
						case 6:which=(1,0);break;
						case 7:which=(-1,1);break;
						case 8:which=(0,1);break;
						case 9:which=(1,1);break;
						default:return;break;
					}
					if(goalset)derp.goalpoint=derp.goalpoint+which*64;
					else derp.goalpoint=derp.pos.xy+which*64;
					goalset=true;
					ppp.A_Log(string.format(Stringtable.Localize("$DERP_GOALSETTO"),derp.goalpoint.x,derp.goalpoint.y),true);
				}else if(
					cmd==556&&derp.stuckline
				){
					badcommand=false;
					derp.setstatelabel("unstuck");
				}else if(cmd==123){
					badcommand=false;
					int ammo=derp.ammo;
					ppp.A_Log(string.format(Stringtable.Localize("$DERP_REPORTIN1"),derp.botid,derp.pos.x,derp.pos.y,ammo>0?string.format(Stringtable.Localize("$DERP_REPORTIN2"),derp.ammo):Stringtable.Localize("$DERP_REPORTIN3")),true);
				}
				if(goalset){
					derp.movestamina=int(20-(level.vec2diff(derp.pos.xy,derp.goalpoint)).length()/derp.speed);
					derp.goalangle=derp.angletogoal();
					derp.setstatelabel("turn");
				}
			}
		}
		if(badcommand){
			let dpu=DERPUsable(ppp.findinventory("DERPUsable"));
			ppp.A_Log(string.format(Stringtable.Localize("$DERP_BADCOMMAND"),dpu?dpu.weaponstatus[DERPS_BOTID]:1),true);
		}
	}
}
class DERPController:HDWeapon{
	default{
		+inventory.invbar
		+weapon.wimpy_weapon
		+nointeraction
		+hdweapon.droptranslation
		inventory.icon "DERPA5";
		weapon.selectionorder 1012;
	}
	array<derpbot> derps;
	action derpbot A_UpdateDerps(bool resetindex=true){
		return invoker.UpdateDerps(resetindex);
	}
	derpbot UpdateDerps(bool resetindex=true){
		derps.clear();
		if(!owner)return null;
		ThinkerIterator derpfinder=thinkerIterator.Create("DERPBot");
		derpbot mo;
		while(mo=DERPBot(derpfinder.Next())){
			if(
				mo.master==owner
				&&mo.distance3d(owner)<frandom(1024,2048)
			)derps.push(mo);
		}
		if(resetindex)weaponstatus[DRPCS_INDEX]=0;
		if(!derps.size()){
			GoAwayAndDie();
			return null;
		}
		derpbot ddd=derps[0];
		ddd.oldcmd=ddd.cmd;
		return ddd;
	}
	static void GiveController(actor caller){
		if(!caller)return;
		caller.A_SetInventory("DERPController",1);
		caller.findinventory("DERPController").binvbar=true;
		let ddc=DERPController(caller.findinventory("DERPController"));
		ddc.updatederps(false);
		if(!ddc.derps.size())caller.dropinventory(ddc);
	}
	int NextDerp(){
		int newindex=weaponstatus[DRPCS_INDEX]+1;
		if(newindex>=derps.size())newindex=0;
		if(weaponstatus[DRPCS_INDEX]!=newindex){
			owner.A_Log(Stringtable.Localize("$DERP_SWITCHING"),true);
			weaponstatus[DRPCS_INDEX]=newindex;
		}
		return newindex;
	}
	action void Abort(){
		A_Log(Stringtable.Localize("$DERP_NODERPS"),true);
		A_SelectWeapon("HDFist");
		setweaponstate("nope");
		dropinventory(invoker);
	}
	override inventory CreateTossable(int amt){
		if(
			(derps.size()&&derps[NextDerp()])
			||updatederps(false)
		)return null;
		return weapon.createtossable(amt);
	}
	override string gethelptext(){
		LocalizeHelp();
		return
		LWPHELP_FIREMODE..StringTable.Localize("$DERPCWH_FMODE")
		..LWPHELP_FIRESHOOT
		..LWPHELP_ALTFIRE..StringTable.Localize("$DERPCWH_ALTFIRE")
		..LWPHELP_USE..StringTable.Localize("$DERPCWH_USE")
		..LWPHELP_RELOAD..StringTable.Localize("$DERPCWH_RELOAD")
		..LWPHELP_UNLOAD..StringTable.Localize("$DERPCWH_UNLOAD")
		..LWPHELP_DROP..StringTable.Localize("$DERPCWH_DROP")
		;
	}
	override void DrawSightPicture(
		HDStatusBar sb,HDWeapon hdw,HDPlayerPawn hpl,
		bool sightbob,vector2 bob,double fov,bool scopeview,actor hpc
	){
		if(
			!derps.size()
			||weaponstatus[DRPCS_INDEX]>=derps.size()
		)return;
		let derpcam=derps[weaponstatus[DRPCS_INDEX]];
		if(!derpcam)return;
		bool dead=(derpcam.health<1);
		int scaledyoffset=46;
		name ctex="HDXCAM_DERP";
		texman.setcameratotexture(derpcam,ctex,60);
		sb.drawimage(
			ctex,(0,scaledyoffset)+bob,sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER,
			alpha:dead?frandom[derpyderp](0.6,0.9):1.,scale:((0.25/1.2),0.25)
		);
		sb.drawimage(
			"tbwindow",(0,scaledyoffset)+bob,sb.DI_SCREEN_CENTER|sb.DI_ITEM_CENTER,
			scale:(1,1)
		);
		if(!dead)sb.drawimage(
			"redpxl",(0,scaledyoffset)+bob,sb.DI_SCREEN_CENTER|sb.DI_ITEM_TOP,
			alpha:0.4,scale:(2,2)
		);
		sb.drawnum(dead?0:max(0,derpcam.ammo),
			24+bob.x,22+bob.y,sb.DI_SCREEN_CENTER,Font.CR_RED,0.4
		);
		int cmd=dead?0:derpcam.oldcmd;
		sb.drawnum(cmd,
			24+bob.x,32+bob.y,sb.DI_SCREEN_CENTER,cmd==3?Font.CR_BRICK:cmd==1?Font.CR_GOLD:Font.CR_LIGHTBLUE,0.4
		);
	}
	states{
	select:
		TNT1 A 10{invoker.weaponstatus[DRPCS_TIMER]=3;}
		goto super::select;
	ready:
		TNT1 A 1{
			if(!invoker.derps.size()||invoker.weaponstatus[DRPCS_INDEX]>=invoker.derps.size()
				||justpressed(BT_USER1)
			){
				a_updatederps();
				if(!invoker.derps.size()){
					Abort();
				}
				return;
			}
			A_WeaponReady(WRF_NOFIRE|WRF_ALLOWUSER3);
			derpbot ddd=invoker.derps[invoker.weaponstatus[DRPCS_INDEX]];
			if(!ddd){
				if(ddd=a_updatederps())A_Log(Stringtable.Localize("$DERP_NOTFOUND"),true);
				else{
					Abort();
				}
				return;
			}
			int bt=player.cmd.buttons;
			if(
				ddd.health<1
				||(
					bt
					&&!invoker.weaponstatus[DRPCS_TIMER]
					&&ddd.distance3d(self)>frandom(0.9,1.1)*DERP_CONTROLRANGE
				)
			){
				A_Log(Stringtable.Localize("$DERP_LASTPOS1")..int(ddd.pos.x)+random(-100,100)..Stringtable.Localize("$DERP_LASTPOS2")..int(ddd.pos.y)+random(-100,100)..Stringtable.Localize("$DERP_LASTPOS3"),true);
				ddd.cmd=ddd.oldcmd;
				invoker.derps.delete(invoker.weaponstatus[DRPCS_INDEX]);
				if(!invoker.derps.size()){
					A_SelectWeapon("HDFist");
					invoker.GoAwayAndDie();
				}
				return;
			}
			int cmd=ddd.oldcmd;
			bool moved=false;
			if(justpressed(BT_UNLOAD)){
				cmd=2;
				A_Log(Stringtable.Localize("$DERP_IDLEMODE"),true);
			}else if(justpressed(BT_RELOAD)){
				cmd++;
				if(cmd>4)cmd=1;
				if(cmd==DERP_IDLE)A_Log(Stringtable.Localize("$DERP_IDLEMODE"),true);
				else if(cmd==DERP_WATCH)A_Log(Stringtable.Localize("$DERP_WATCHMODE"),true);
				else if(cmd==DERP_TURRET)A_Log(Stringtable.Localize("$DERP_WATCH360MODE"),true);
				else if(cmd==DERP_PATROL)A_Log(Stringtable.Localize("$DERP_PATROLMODE"),true);
			}
			ddd.oldcmd=cmd;
			if(bt&BT_FIREMODE){
				ddd.cmd=DERP_IDLE;
				if(!invoker.weaponstatus[DRPCS_TIMER]){
					if(
						justpressed(BT_ATTACK)
					){
						invoker.weaponstatus[DRPCS_TIMER]+=4;
						if(ddd.ammo>0){
							ddd.setstatelabel("noreallyfire");
							ddd.tics=2; //for some reason a 1-tic firing frame won't show
						}else ddd.setstatelabel("noammo");
						return;
					}else if(
						(
							player.cmd.forwardmove
							||(bt&BT_ALTATTACK)
							||(bt&BT_USE)
						)
						&&!invoker.weaponstatus[DRPCS_TIMER]
					){
						invoker.weaponstatus[DRPCS_TIMER]+=2;
						ddd.A_DerpCrawlSound();
						vector2 nv2=(cos(ddd.angle),sin(ddd.angle))*ddd.speed;
						if(bt&BT_USE||player.cmd.forwardmove<0)nv2*=-1;
						if(ddd.floorz>=ddd.pos.z)ddd.TryMove(ddd.pos.xy+nv2,true);
						moved=true;
					}
				}
				int yaw=clamp(GetMouseX(true)>>5,-10,10);
				if(!yaw)yaw=clamp(-player.cmd.sidemove,-10,10);
				int ptch=clamp(GetMouseY(true)>>5,-10,10);
				if(yaw||ptch){
					ddd.A_DerpCrawlSound(150);
					ddd.pitch=clamp(ddd.pitch-clamp(ptch,-10,10),-90,60);
					ddd.angle+=clamp(yaw,-DERP_MAXTICTURN,DERP_MAXTICTURN);
					ddd.goalangle=999;
					ddd.movestamina=1001;
					if(yaw)moved=true;
				}
			}else{
				ddd.cmd=cmd;
				if(cmd==DERP_PATROL&&ddd.movestamina>=1000)ddd.movestamina=0;
			}
			if(moved&&!!ddd.stuckline){
				ddd.setstatelabel("unstuck");
			}
			if(!invoker.bweaponbusy&&hdplayerpawn(self))hdplayerpawn(self).nocrosshair=0;
			if(invoker.weaponstatus[DRPCS_TIMER]>0)invoker.weaponstatus[DRPCS_TIMER]--;
		}goto readyend;
	user3:
		---- A 0 A_MagManager("HD9mMag15");
		goto ready;
	hack:
		---- A 5 A_Log(Stringtable.Localize("$DERP_FETCHDEVICES"),true);
		---- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 1 A_WeaponReady(WRF_NOFIRE|WRF_ALLOWUSER3);
		---- AAAAAAAAAAAAAA 1 A_WeaponMessage("\cj"..random(10000,99999).." "..random(10000,99999),10);
		---- A 0{
			if(random(0,7))invoker.HackNearbyDerps();
			A_StartSound("derp/crawl",CHAN_WEAPON);
		}
		goto nope;
	spawn:
		TNT1 A 0;
		stop;
	}
	//attempt to use the controller to connect to another D.E.R.P.
	bool HackNearbyDerps(){
		if(!owner||!derps.size())return false;
		ThinkerIterator derpfinder=thinkerIterator.Create("DERPBot");
		derpbot mo;
		while(mo=DERPBot(derpfinder.Next())){
			if(
				mo.master!=owner
				&&mo.distance3d(owner)<frandom(0.9,1.1)*DERP_CONTROLRANGE
			){
				let opponent=mo.master;
				int hackable=0;
				if(mo.checksight(owner))hackable+=2;
				if(
					!opponent
					||!mo.checksight(opponent)
					||mo.distance3d(opponent)>(DERP_CONTROLRANGE*0.6)
				)hackable+=3;
				if(random(0,hackable)){
					mo.master=owner;
					if(opponent){
						let opcon=DERPController(opponent.findinventory("DERPController"));
						if(opcon)opcon.updatederps(false);
						opponent.A_Log(Stringtable.Localize("$DERP_CONNECTIONFAILURE1")..int(mo.pos.x)+random(-100,100)..Stringtable.Localize("$DERP_CONNECTIONFAILURE2")..int(mo.pos.y)+random(-100,100)..Stringtable.Localize("$DERP_CONNECTIONFAILURE3"),true);
					}
					owner.A_Log(Stringtable.Localize("$DERP_CONNECTED1")..int(mo.pos.x)+random(-100,100)..Stringtable.Localize("$DERP_CONNECTED2")..int(mo.pos.y)+random(-100,100)..Stringtable.Localize("$DERP_CONNECTED3"),true);
					mo.cmd=DERP_IDLE;
					if(owner.player)mo.bfriendly=true;else mo.bfriendly=owner.bfriendly;
					mo.A_StartSound("derp/hacked",69420);
					updatederps();
					return true;
				}else{
					mo.target=owner;
					string omghax=Stringtable.Localize("$DERP_CONNECTIONATTEMPTMADE1")..owner.gettag()..Stringtable.Localize("$DERP_CONNECTIONATTEMPTMADE2")..int(owner.pos.x)+random(-10,10)..Stringtable.Localize("$DERP_CONNECTIONATTEMPTMADE3")..int(owner.pos.y)+random(-10,10)..Stringtable.Localize("$DERP_CONNECTIONATTEMPTMADE4");
					if(opponent)opponent.A_Log(omghax,true);
					else mo.cmd=DERP_PATROL;
					owner.A_Log(omghax,true);
					return false;
				}
			}
		}
		owner.A_Log(Stringtable.Localize("$DERP_REMOTELOGINFAILED"),true);
		return false;
	}
}